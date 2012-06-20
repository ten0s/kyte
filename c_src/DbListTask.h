/**
 * This file is a part of Kyte released under the MIT licence.
 * See the LICENCE file for more information
 */

#ifndef _DbListTask_h
#define _DbListTask_h

#include "kyte.h"
#include "DbGenericTask.h"

namespace kyte {
	class DbListTask : public DbGenericTask {
	private:
		ERL_NIF_TERM _Key;
	public:
		DbListTask();
		virtual ~DbListTask();

		virtual void Run();

    private:
		void ReplyError(ErlNifEnv* env, const char* error);
	};
}

#endif // _DbListTask_h
