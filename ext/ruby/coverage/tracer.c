// Released under the MIT License.
// Copyright, 2025, by Samuel Williams.

#include "tracer.h"

#include <ruby.h>
#include <ruby/debug.h>

static const int DEBUG = 0;

static ID id_call;
static ID id_path;

struct Ruby_Coverage_Tracer {
	// The Ruby callback: called with (path, iseq) the first time a new file is
	// compiled. iseq is the RubyVM::InstructionSequence from the script_compiled
	// event. Must return an Array to use as the line-count store, or nil to
	// skip the file.
	VALUE callback;

	// Hash: { path String => counts Array }
	VALUE counts;

	// Cache of the most recently seen rb_sourcefile() pointer. Stable for the
	// lifetime of the current ISeq, so pointer equality is an O(1) same-file
	// check without a hash lookup on every line event.
	uintptr_t last_path_pointer;

	// The counts Array for the file identified by last_path_pointer.
	VALUE last_counts;

	// Re-entrancy guard. Set while the user callback is being invoked so that
	// any RUBY_EVENT_LINE events fired by the callback itself are ignored.
	int in_callback;
};

static void Ruby_Coverage_Tracer_mark(void *pointer)
{
	struct Ruby_Coverage_Tracer *tracer = pointer;
	rb_gc_mark_movable(tracer->callback);
	rb_gc_mark_movable(tracer->counts);
	rb_gc_mark_movable(tracer->last_counts);
}

static void Ruby_Coverage_Tracer_free(void *pointer)
{
	xfree(pointer);
}

static void Ruby_Coverage_Tracer_compact(void *pointer)
{
	struct Ruby_Coverage_Tracer *tracer = pointer;
	tracer->callback    = rb_gc_location(tracer->callback);
	tracer->counts      = rb_gc_location(tracer->counts);
	tracer->last_counts = rb_gc_location(tracer->last_counts);
}

static const rb_data_type_t Ruby_Coverage_Tracer_type = {
	.wrap_struct_name = "Ruby::Coverage::Tracer",
	.function = {
		.dmark    = Ruby_Coverage_Tracer_mark,
		.dfree    = Ruby_Coverage_Tracer_free,
		.dsize    = NULL,
		.dcompact = Ruby_Coverage_Tracer_compact,
	},
	.flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

struct Ruby_Coverage_Tracer_CurrentISeq {
	VALUE iseq;
};

struct Ruby_Coverage_Tracer_CallbackArguments {
	struct Ruby_Coverage_Tracer *tracer;
	VALUE path;
	VALUE iseq;
};

static VALUE Ruby_Coverage_Tracer_current_iseq_callback(const rb_debug_inspector_t *debug_inspector, void *data)
{
	struct Ruby_Coverage_Tracer_CurrentISeq *current_iseq = data;
	current_iseq->iseq = rb_debug_inspector_frame_iseq_get(debug_inspector, 0);

	return Qnil;
}

static VALUE Ruby_Coverage_Tracer_current_iseq(void)
{
	struct Ruby_Coverage_Tracer_CurrentISeq current_iseq = {.iseq = Qnil};
	rb_debug_inspector_open(Ruby_Coverage_Tracer_current_iseq_callback, &current_iseq);

	return current_iseq.iseq;
}

static VALUE Ruby_Coverage_Tracer_call_callback(VALUE data)
{
	struct Ruby_Coverage_Tracer_CallbackArguments *arguments = (struct Ruby_Coverage_Tracer_CallbackArguments *)data;

	return rb_funcall(arguments->tracer->callback, id_call, 2, arguments->path, arguments->iseq);
}

static VALUE Ruby_Coverage_Tracer_leave_callback(VALUE data)
{
	struct Ruby_Coverage_Tracer_CallbackArguments *arguments = (struct Ruby_Coverage_Tracer_CallbackArguments *)data;
	arguments->tracer->in_callback -= 1;

	return Qnil;
}

static VALUE Ruby_Coverage_Tracer_invoke_callback(struct Ruby_Coverage_Tracer *tracer, VALUE path, VALUE iseq)
{
	struct Ruby_Coverage_Tracer_CallbackArguments arguments = {
		.tracer = tracer,
		.path = path,
		.iseq = iseq,
	};

	tracer->in_callback += 1;

	return rb_ensure(
		Ruby_Coverage_Tracer_call_callback,
		(VALUE)&arguments,
		Ruby_Coverage_Tracer_leave_callback,
		(VALUE)&arguments
	);
}

static VALUE Ruby_Coverage_Tracer_allocate(VALUE klass)
{
	struct Ruby_Coverage_Tracer *tracer;
	VALUE self = TypedData_Make_Struct(klass, struct Ruby_Coverage_Tracer, &Ruby_Coverage_Tracer_type, tracer);

	tracer->callback          = Qnil;
	tracer->counts            = rb_hash_new();
	tracer->last_path_pointer = 0;
	tracer->last_counts       = Qnil;
	tracer->in_callback       = 0;

	return self;
}

static VALUE Ruby_Coverage_Tracer_initialize(VALUE self)
{
	struct Ruby_Coverage_Tracer *tracer;
	TypedData_Get_Struct(self, struct Ruby_Coverage_Tracer,
	                     &Ruby_Coverage_Tracer_type, tracer);

	RB_OBJ_WRITE(self, &tracer->callback, rb_block_proc());

	return self;
}

// Installed via rb_add_event_hook2 with RUBY_EVENT_HOOK_FLAG_RAW_ARG.
// Fires when any Ruby script is compiled, with access to the trace argument.
//
// Retrieves the compiled RubyVM::InstructionSequence via
// rb_tracearg_instruction_sequence and invokes the user callback immediately,
// so the counts array is registered before the first line event fires.
// Also invalidates the rb_sourcefile() pointer cache so the line hook
// re-evaluates which counts array to use.
static void Ruby_Coverage_Tracer_on_script_compiled(VALUE data, const rb_trace_arg_t *trace_arg)
{
	struct Ruby_Coverage_Tracer *tracer;
	TypedData_Get_Struct(data, struct Ruby_Coverage_Tracer,
	                     &Ruby_Coverage_Tracer_type, tracer);

	tracer->last_path_pointer = 0;

	// Guard the entire body: rb_funcall (for #path and the user callback) can
	// fire RUBY_EVENT_LINE, and without the guard on_line would run and
	// potentially invoke the user callback before we've finished here.
	if (tracer->in_callback) return;

	VALUE iseq = rb_tracearg_instruction_sequence((rb_trace_arg_t *)trace_arg);
	if (NIL_P(iseq)) { return; }

	VALUE path = rb_funcall(iseq, id_path, 0);
	if (NIL_P(path)) { return; }

	// Reuse existing counts for re-evals of the same path so hit counts
	// accumulate rather than reset.
	if (!NIL_P(rb_hash_lookup(tracer->counts, path))) { return; }

	VALUE counts = Ruby_Coverage_Tracer_invoke_callback(tracer, path, iseq);

	if (!NIL_P(counts)) {
		rb_hash_aset(tracer->counts, path, counts);
	}
}

// Installed via rb_add_event_hook. Fires on every new source line.
//
// Uses rb_sourcefile() pointer comparison as an O(1) same-file sentinel.
// On first entry to a new file, checks if the script_compiled hook already
// registered a counts array. If not (file was compiled before the tracer
// started), falls back to rb_profile_frames to get the iseq and invokes the
// user callback, matching the behaviour of the script_compiled path.
static void Ruby_Coverage_Tracer_on_line(rb_event_flag_t event, VALUE data, VALUE self, ID method_id, VALUE klass)
{
	struct Ruby_Coverage_Tracer *tracer;
	TypedData_Get_Struct(data, struct Ruby_Coverage_Tracer, &Ruby_Coverage_Tracer_type, tracer);

	if (tracer->in_callback) return;

	uintptr_t current_path_pointer = (uintptr_t)rb_sourcefile();

	if (tracer->last_path_pointer != current_path_pointer) {
		tracer->last_path_pointer = current_path_pointer;

		const char *path_cstr = rb_sourcefile();
		VALUE counts = Qnil;

		if (path_cstr) {
			VALUE path = rb_str_new_cstr(path_cstr);
			counts = rb_hash_lookup(tracer->counts, path);

			if (NIL_P(counts)) {
				// File was compiled before the tracer started; inspect the current
				// frame to recover the active instruction sequence.
				VALUE iseq = Ruby_Coverage_Tracer_current_iseq();

				if (!NIL_P(iseq)) {
					counts = Ruby_Coverage_Tracer_invoke_callback(tracer, path, iseq);

					if (!NIL_P(counts)) {
						rb_hash_aset(tracer->counts, path, counts);
					}
				}
			}
		}

		RB_OBJ_WRITE(data, &tracer->last_counts, counts);
	}

	if (NIL_P(tracer->last_counts)) return;

	int line = rb_sourceline();

	// Counts are 1-indexed: index 0 is unused (nil), index N is the hit count
	// for source line N. Grow the array if necessary.
	while (RARRAY_LEN(tracer->last_counts) <= line) {
		rb_ary_push(tracer->last_counts, Qnil);
	}

	VALUE current = rb_ary_entry(tracer->last_counts, line);
	rb_ary_store(tracer->last_counts, line,
	             NIL_P(current) ? INT2FIX(1) : INT2FIX(FIX2INT(current) + 1));
}

static VALUE Ruby_Coverage_Tracer_start(VALUE self)
{
	rb_add_event_hook2(
		(rb_event_hook_func_t)Ruby_Coverage_Tracer_on_script_compiled,
		RUBY_EVENT_SCRIPT_COMPILED,
		self,
		RUBY_EVENT_HOOK_FLAG_SAFE | RUBY_EVENT_HOOK_FLAG_RAW_ARG
	);
	rb_add_event_hook(Ruby_Coverage_Tracer_on_line, RUBY_EVENT_LINE, self);

	return self;
}

static VALUE Ruby_Coverage_Tracer_stop(VALUE self)
{
	rb_remove_event_hook_with_data((rb_event_hook_func_t)Ruby_Coverage_Tracer_on_script_compiled, self);
	rb_remove_event_hook_with_data(Ruby_Coverage_Tracer_on_line, self);

	struct Ruby_Coverage_Tracer *tracer;
	TypedData_Get_Struct(self, struct Ruby_Coverage_Tracer, &Ruby_Coverage_Tracer_type, tracer);

	tracer->last_path_pointer = 0;
	RB_OBJ_WRITE(self, &tracer->last_counts, Qnil);

	return self;
}

void Init_Ruby_Coverage_Tracer(VALUE Ruby_Coverage)
{
	id_call = rb_intern("call");
	id_path = rb_intern("path");

	VALUE Ruby_Coverage_Tracer = rb_define_class_under(Ruby_Coverage, "Tracer", rb_cObject);

	rb_define_alloc_func(Ruby_Coverage_Tracer, Ruby_Coverage_Tracer_allocate);
	rb_define_method(Ruby_Coverage_Tracer, "initialize", Ruby_Coverage_Tracer_initialize, 0);
	rb_define_method(Ruby_Coverage_Tracer, "start",      Ruby_Coverage_Tracer_start,      0);
	rb_define_method(Ruby_Coverage_Tracer, "stop",       Ruby_Coverage_Tracer_stop,       0);
}
