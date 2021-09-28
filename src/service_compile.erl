-module(service_compile).

-export([file/2,file/3]).

-include_lib("include/compiler_macros.hrl").

file(PkgName,Filename) ->     
    {InterfaceName, Code, Header} = gen_interface(PkgName,"srv","",Filename,scanner,service_parser),
    {ok,InterfaceName, Code, Header}.

file(PkgName,ActionName, Filename) ->     
    {InterfaceName, Code, Header} = gen_interface(PkgName,"action",ActionName,Filename,scanner,service_parser),
    {ok,InterfaceName, Code, Header}.

gen_interface(PkgName,Tag, ActionName, Filename,Scanner,Parser) -> 
    {ok,Bin} = file:read_file(Filename),
    %io:format(Bin),
    % checking the work of the scanner
    case Scanner:string(binary_to_list(Bin)) of
        {ok,Tokens,_} -> 
            %io:format("~p\n",[Tokens]),
            % checking the work of the Yecc
            case Parser:parse(Tokens) of
                {ok,Res} ->% print_parsed_info(Res),
                     generate_interface(PkgName,Tag, ActionName, Filename, Res);
                Else -> io:format("Service Parser failed: ~p\n",[Else])
            end;
        ErrorInfo -> io:format("Service Scanner failed: ~p\n",[ErrorInfo])
    end.


generate_interface(PkgName, Tag, ActionName, Filename,{Request,Reply}) ->
    Name = filename:basename(Filename,".srv"),
    InterfaceName = rosie_utils:file_name_to_interface_name(ActionName++Name),
    HEADER_DEF = string:to_upper(InterfaceName++"_srv"++"_hrl"),
    IncludedHeaders = rosie_utils:produce_includes(Request++Reply),

    {RequestInput,RequestOutput, SerializerRequest,DeserializerRequest}  = rosie_utils:produce_in_out(Request),
    RequestSizes = string:join(rosie_utils:get_bitsizes(Request),"+"),
    RequestRecordData = rosie_utils:produce_record_def(Request),

    {ReplyInput,ReplyOutput,SerializerReply,DeserializerReply}  = rosie_utils:produce_in_out(Reply),
    ReplySizes = string:join(rosie_utils:get_bitsizes(Reply),"+"),
    ReplyRecordData = rosie_utils:produce_record_def(Reply),
    % string of code as output
    {InterfaceName++"_srv", 
"-module("++InterfaceName++"_srv).

-export([get_name/0, get_type/0, serialize_request/2, serialize_reply/2, parse_request/1, parse_reply/1]).

% self include
-include(\""++InterfaceName++"_srv.hrl\").

% GENERAL

get_name() ->
        \""++case ActionName /= "" of
            true -> string:lowercase(ActionName)++"/_action/";
            false -> "" 
            end
        ++rosie_utils:file_name_to_interface_name(Name)++"\".

get_type() ->
        \""++PkgName++"::"++Tag++"::dds_::" 
        ++case ActionName /= "" of
            true -> ActionName++"_";
            false -> "" 
            end
        ++Name++"_"++"\".

"++case rosie_utils:items_contain_usertyped_arrays(Request++Reply) of
    true -> ?PARSE_N_TIMES_CODE; %paste extra code
    false -> "" 
    end
++case rosie_utils:items_contain_std_arrays(Request++Reply) of
    true -> ?BIN_TO_BIN_LIST_CODE; %paste extra code
    false -> "" 
    end
++
"
% CLIENT
serialize_request(Client_ID,#"++InterfaceName++"_rq{"++RequestInput++"}) -> 
        <<Client_ID:8/binary, 1:64/little,"++SerializerRequest++">>.

parse_reply(<<Client_ID:8/binary, 1:64/little, Payload_0/binary>>) ->
        "++DeserializerReply++",
        { Client_ID, #"++InterfaceName++"_rp{"++ReplyOutput++"} }.

% SERVER        
serialize_reply(Client_ID,#"++InterfaceName++"_rp{"++ReplyInput++"}) -> 
        <<Client_ID:8/binary, 1:64/little, "++SerializerReply++">>.

parse_request(<<Client_ID:8/binary, 1:64/little, Payload_0/binary>>) ->
        "++DeserializerRequest++",
        { Client_ID, #"++InterfaceName++"_rq{"++RequestOutput++"} }.

",
% .hrl
"-ifndef("++HEADER_DEF++").
-define("++HEADER_DEF++", true).

"++IncludedHeaders++"
% bit size should be ignored
%-define("++Name++"_rq_bitsize, "++RequestSizes++" ).
%-define("++Name++"_rp_bitsize, "++ReplySizes++" ).

-record("++InterfaceName++"_rq,{"++RequestRecordData++"}).
-record("++InterfaceName++"_rp,{"++ReplyRecordData++"}).

-endif.
"}.
