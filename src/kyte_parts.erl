% This file is a part of Kyte released under the MIT licence.
% See the LICENCE file for more information

-module(kyte_parts).

-export([
	init/5,
	partition_init_notify/3,
	close_partitions/1,
	fold/3,
	choose_partition/3
]).

-include("kyte.hrl").

-record(state, {
	type :: kyte_partitioning_type(),
	partitions :: dict()
}).

-type state() :: #state{}.
-type part_id() :: single | {part, integer()}.

-spec init(pid(), pid(), pid(), string(), kyte_partitioning_type()) -> state().
-spec partition_init_notify( state(), part_id(), pid() ) -> state().
-spec close_partitions(state()) -> ok.

-type fold_fun() :: any(). %% fun((pid(), any()) -> any()).
-spec fold(state(), fold_fun(), any()) -> any().

init( Pool, DbSrv, PartsSup, DbFile, single) ->
	{ok, SinglePartSpec} = spec_single_partition(single, Pool, DbSrv, DbFile),
	{ok, SinglePartSrv} = supervisor:start_child(PartsSup, SinglePartSpec),
	Dict = dict:store(single, SinglePartSrv, dict:new()),
	#state{
		type = single,
		partitions = dict:store(single, SinglePartSrv, Dict )
	};

init( Pool, DbSrv, PartsSup, DbFile, Type = {post_hash, PC, _HF}) ->
	{ok, Dict} = start_multiple_partitions(dict:new(), PC, Pool, DbSrv, PartsSup, DbFile),
	#state{
		type = Type,
		partitions = Dict
	}.

partition_init_notify( PartsCtx = #state{ type = single }, single, PartSrv ) ->
	{ ok, PartsCtx #state{
		partitions = dict:store( single, PartSrv, dict:new() )
	} };

partition_init_notify( PartsCtx = #state{ 
							type = {post_hash, _PC, _HF},
							partitions = Dict
						}, ID, PartSrv
) ->
	{ ok, PartsCtx #state{
		partitions = dict:store( ID, PartSrv, Dict )
	} }.

close_partitions(#state{
	partitions = Dict
}) ->
	lists:foreach( 
		fun({_, PartSrv}) ->
			_Ret = gen_server:call(PartSrv, db_close, infinity)
		end,
		dict:to_list(Dict) ),
	ok.

fold(#state{
	partitions = Dict
}, Fun, Acc0) ->
	lists:foldl( 
		fun({_ID, P}, A) -> Fun(P, A) end, 
	Acc0, dict:to_list(Dict) ).


choose_partition(#state{
	type = single,
	partitions = Dict
}, _K, _Kenc) ->
	dict:fetch(single, Dict);

choose_partition(#state{
	type = {post_hash, Count, HashF},
	partitions = Dict
}, _K, Kenc) ->
	Kh = HashF(Kenc),
	Bits = size(Kh) * 8,
	<<Hash:Bits/unsigned>> = Kh,
	PartIdx = ( Hash rem Count ) + 1,
	dict:fetch({part, PartIdx}, Dict).


%%% Internal

start_multiple_partitions( Dict, 0, _Pool, _DbSrv, _PartsSup, _DbFile ) ->
	{ok, Dict};

start_multiple_partitions( Dict, PC, Pool, DbSrv, PartsSup, DbFile ) ->
	{ ok, PartSpec } = spec_single_partition( { part, PC }, Pool, DbSrv, file_name( DbFile, PC ) ),
	{ ok, PartSrv } = supervisor:start_child( PartsSup, PartSpec ),
	start_multiple_partitions(
		dict:store({part, PC}, PartSrv, Dict),
		PC - 1, Pool, DbSrv, PartsSup, DbFile
	).

spec_single_partition( ID, Pool, DbSrv, DbFile ) ->
	{ ok, 
		{ ID, 
			{ kyte_db_partition_srv, start_link, [ ID, Pool, DbSrv, DbFile ] }, 
			transient, 30000, worker, [ kyte_db_partition_srv ] 
		}
	}.

file_name(DbFile, Part ) ->
	lists:flatten( io_lib:format( DbFile, [ Part ] ) ).




% file_names(DbFile, PartsCount) ->
% 	lists:map(fun(Idx) ->
% 		lists:flatten(io_lib:format(DbFile, [Idx]))
% 	end, lists:seq(1, PartsCount)).

% choose_partition(K, HF, Parts) ->
% 	Kh = HF(K),
% 	Bits = size(Kh) * 8,
% 	<<Hash:Bits/unsigned>> = Kh,
% 	PartIdx = ( Hash rem length(Parts) ) + 1,
% 	{ok, lists:nth(PartIdx, Parts)}.

% with_partition(K, HF, Parts, Func) ->
% 	{ok, Part} = choose_partition(K, HF, Parts),
% 	Func(Part).

%%% Internal



