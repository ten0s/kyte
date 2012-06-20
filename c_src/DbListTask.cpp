/**
 * This file is a part of Kyte released under the MIT licence.
 * See the LICENCE file for more information
 */

#include "DbListTask.h"

#ifndef KYTE_MAX_KEY_SIZE
#define KYTE_MAX_KEY_SIZE 1024
#endif // KYTE_MAX_KEY_SIZE

#ifndef KYTE_MAX_VALUE_SIZE
#define KYTE_MAX_VALUE_SIZE 64000
#endif // KYTE_MAX_VALUE_SIZE

namespace kyte {
  DbListTask::DbListTask() {}
  DbListTask::~DbListTask() {}

  void DbListTask::Run() {
	if (!EnsureDB()) return;

	// create output list.
	ERL_NIF_TERM list = enif_make_list(Env(), 0);

	// create cursor.
	kyotocabinet::DB::Cursor* cur = DB()->cursor();
	if (!cur) {
	  ReplyError(Env(), DB()->error().name());
	  return;
	}
	// unfortunately jump_back() is not implemented :(
	if (!cur->jump()) {
	  delete cur;
	  ReplyError(Env(), DB()->error().name());
	  return;
	}

	size_t size;
	char* data;
	ErlNifBinary binKey;
	ErlNifBinary binValue;

	for(;;) {
	  // read key.
	  size = 0;
	  data = cur->get_key(&size, false);
	  if (!data) {
		ReplyError(Env(), DB()->error().name());
		break;
	  } else {
		// alloc & init binKey.
		if (!enif_alloc_binary(size, &binKey)) {
		  delete []data;
		  ReplyError(Env(), "alloc");
		  break;
		}
		binKey.size = size;
		memcpy(binKey.data, data, size);
		delete []data;
	  }

	  // read value.
	  size = 0;
	  data = cur->get_value(&size, false);
	  if (!data) {
		ReplyError(Env(), DB()->error().name());
		break;
	  } else {
		// alloc & init binValue.
		if (!enif_alloc_binary(size, &binValue)) {
		  enif_release_binary(&binKey);
		  delete []data;
		  ReplyError(Env(), "alloc");
		  break;
		}
		binValue.size = size;
		memcpy(binValue.data, data, size);
		delete []data;
	  }

	  // make {key, value} tuple.
	  ERL_NIF_TERM head = enif_make_tuple2(Env(),
		enif_make_binary(Env(), &binKey),
		enif_make_binary(Env(), &binValue));

	  // prepend to list.
	  list = enif_make_list_cell(Env(), head, list);

	  if (!cur->step()) {
		break;
	  }
	}
	delete cur;

	// as Cursor::jump_back() is not implemented we must
	// reverse the list.
	ERL_NIF_TERM reversed_list;
	if (!enif_make_reverse_list(Env(), list, &reversed_list)) {
	  	ReplyError(Env(), DB()->error().name());
	} else {
	  Reply(enif_make_tuple2(Env(),
		enif_make_atom(Env(), "ok"), reversed_list));
	}
  }

  void DbListTask::ReplyError(ErlNifEnv* env, const char* error) {
	Reply(enif_make_tuple2(env,
		enif_make_atom(env, "error"),
		enif_make_string(env, error, ERL_NIF_LATIN1)));
  }
}
