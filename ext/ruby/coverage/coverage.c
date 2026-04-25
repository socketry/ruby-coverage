// Released under the MIT License.
// Copyright, 2025, by Samuel Williams.

#include "coverage.h"
#include "tracer.h"

void Init_Ruby_Coverage(void)
{
	VALUE Ruby = rb_define_module("Ruby");
	VALUE Ruby_Coverage = rb_define_module_under(Ruby, "Coverage");

	Init_Ruby_Coverage_Tracer(Ruby_Coverage);
}
