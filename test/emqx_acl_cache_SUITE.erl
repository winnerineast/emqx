%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_acl_cache_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("eunit/include/eunit.hrl").

all() -> emqx_ct:all(?MODULE).

init_per_suite(Config) ->
    emqx_ct_helpers:boot_modules(all),
    emqx_ct_helpers:start_apps([]),
    Config.

end_per_suite(_Config) ->
    emqx_ct_helpers:stop_apps([]).

%%--------------------------------------------------------------------
%% Test cases
%%--------------------------------------------------------------------

t_clean_acl_cache(_) ->
    {ok, Client} = emqtt:start_link([{clientid, <<"emqx_c">>}]),
    {ok, _} = emqtt:connect(Client),
    {ok, _, _} = emqtt:subscribe(Client, <<"t2">>, 0),
    emqtt:publish(Client, <<"t1">>, <<"{\"x\":1}">>, 0),
    ct:sleep(100),
    ClientPid = case emqx_cm:lookup_channels(<<"emqx_c">>) of
        [Pid] when is_pid(Pid) ->
            Pid;
        Pids when is_list(Pids) ->
            lists:last(Pids);
        _ -> {error, not_found}
    end,
    Caches = gen_server:call(ClientPid, list_acl_cache),
    ct:log("acl caches: ~p", [Caches]),
    ?assert(length(Caches) > 0),
    erlang:send(ClientPid, clean_acl_cache),
    ?assertEqual(0, length(gen_server:call(ClientPid, list_acl_cache))),
    emqtt:stop(Client).

% optimize??
t_reload_aclfile_and_cleanall(Config) ->

    RasieMsg = fun() -> Self = self(), #{puback => fun(Msg) -> Self ! {puback, Msg} end,
                                         disconnected => fun(_) ->  ok end,
                                         publish => fun(_) -> ok end } end,

    {ok, Client} = emqtt:start_link([{clientid, <<"emqx_c">>}, {proto_ver, v5}, {msg_handler, RasieMsg()}]),
    {ok, _} = emqtt:connect(Client),

    {ok, PktId} = emqtt:publish(Client, <<"t1">>, <<"{\"x\":1}">>, qos1),

    %% Success publish to broker
    receive
        {puback, #{packet_id := PktId, reason_code := Rc}} ->
            ?assertEqual(16#10, Rc);
        _ ->
            ?assert(false)
    end,

    %% Check acl cache list
    [ClientPid] = emqx_cm:lookup_channels(<<"emqx_c">>),
    ?assert(length(gen_server:call(ClientPid, list_acl_cache)) > 0),

    %% Update acl file and reload mod_acl_internal
    Path = filename:join([testdir(proplists:get_value(data_dir, Config)), "acl2.conf"]),
    ok = file:write_file(Path, <<"{deny, all}.">>),
    OldPath = emqx:get_env(acl_file),
    % application:set_env(emqx, acl_file, Path),
    emqx_mod_acl_internal:reload([{acl_file, Path}]),

    ?assert(length(gen_server:call(ClientPid, list_acl_cache)) == 0),
    {ok, PktId2} = emqtt:publish(Client, <<"t1">>, <<"{\"x\":1}">>, qos1),

    receive
        {puback, #{packet_id := PktId2, reason_code := Rc2}} ->
            %% Not authorized
            ?assertEqual(16#87, Rc2);
        _ ->
            ?assert(false)
    end,
    application:set_env(emqx, acl_file, OldPath),
    file:delete(Path),
    emqx_mod_acl_internal:reload([{acl_file, OldPath}]),
    emqtt:stop(Client).

%% @private
testdir(DataPath) ->
    Ls = filename:split(DataPath),
    filename:join(lists:sublist(Ls, 1, length(Ls) - 1)).

% t_cache_k(_) ->
%     error('TODO').

% t_cache_v(_) ->
%     error('TODO').

% t_cleanup_acl_cache(_) ->
%     error('TODO').

% t_get_oldest_key(_) ->
%     error('TODO').

% t_get_newest_key(_) ->
%     error('TODO').

% t_get_cache_max_size(_) ->
%     error('TODO').

% t_get_cache_size(_) ->
%     error('TODO').

% t_dump_acl_cache(_) ->
%     error('TODO').

% t_empty_acl_cache(_) ->
%     error('TODO').

% t_put_acl_cache(_) ->
%     error('TODO').

% t_get_acl_cache(_) ->
%     error('TODO').

% t_is_enabled(_) ->
%     error('TODO').

