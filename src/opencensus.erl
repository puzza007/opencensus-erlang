%%%------------------------------------------------------------------------
%% Copyright 2017, OpenCensus Authors
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% @doc opencensus main module
%% @end
%%%-------------------------------------------------------------------------
-module(opencensus).

-export([start_trace/0,
         start_trace/1,
         start_trace/3,

         start_span/2,
         start_span/3,
         start_span/4,
         finish_span/1,

         context/1,
         context/2,

         put_attribute/3,
         put_attributes/2,

         add_time_event/2,
         add_time_event/3,

         add_link/2,
         link/4,

         annotation/2,

         message_event/4,

         set_status/3,

         generate_trace_id/0,
         generate_span_id/0]).

-include("opencensus.hrl").

-export_type([trace_id/0,
              span_id/0,
              trace_context/0,
              span/0,
              link/0,
              links/0,
              link_type/0,
              attributes/0,
              annotation/0,
              time_events/0,
              message_event/0,
              message_event_type/0,
              stack_trace/0,
              status/0]).

-type trace_id()           :: non_neg_integer().
-type span_id()            :: non_neg_integer().
-type trace_context()      :: #trace_context{}.
-type span()               :: #span{}.
-type stack_trace()        :: [erlang:stack_item()].
-type attribute_value()    :: any().
-type attributes()         :: #{unicode:unicode_binary() => attribute_value()}.
-type annotation()         :: #annotation{}.
-type message_event()      :: #message_event{}.
-type message_event_type() :: ?MESSAGE_EVENT_TYPE_UNSPECIFIED | ?MESSAGE_EVENT_TYPE_SENT | ?MESSAGE_EVENT_TYPE_RECEIVED.
-type time_events()        :: [{wts:timestamp(), annotation() | message_event()}].
-type link()               :: #link{}.
-type links()              :: [link()].
-type link_type()          :: ?LINK_TYPE_UNSPECIFIED | ?LINK_TYPE_CHILD_LINKED_SPAN | ?LINK_TYPE_PARENT_LINKED_SPAN.
-type status()             :: #status{}.
-type maybe(T)             :: T | undefined.

%%--------------------------------------------------------------------
%% @doc
%% Creates a new trace context if `enabled` is true in the trace context
%% argument or the sampling function returns true. If the sampling returns
%% false then `undefined` is returned.
%% @end
%%--------------------------------------------------------------------
-spec start_trace() -> trace_context().
start_trace()  ->
    start_trace(generate_trace_id(), undefined, undefined).

start_trace(undefined)  ->
    start_trace(generate_trace_id(), undefined, undefined);
start_trace(#trace_context{trace_id=TraceId,
                           span_id=SpanId,
                           enabled=Enabled})  ->
    start_trace(TraceId, SpanId, Enabled);
start_trace(TraceId)  ->
    start_trace(TraceId, undefined, undefined).

start_trace(TraceId, SpanId, Enabled)  ->
    #trace_context{trace_id = TraceId,
                   span_id = SpanId,
                   enabled = oc_sampler:should_sample(TraceId, SpanId, Enabled)}.

%%--------------------------------------------------------------------
%% @doc
%% Starts a new span with a given Trace ID and Parent ID.
%% @end
%%--------------------------------------------------------------------
-spec start_span(unicode:unicode_binary(), maybe(trace_context() | span() | trace_id())) -> maybe(span()).
start_span(_Name, undefined) ->
    undefined;
start_span(Name, #trace_context{trace_id=TraceId,
                                span_id=ParentId}) ->
    start_span(Name, TraceId, ParentId, #{});
start_span(Name, #span{trace_id=TraceId,
                       span_id=ParentId}) ->
    start_span(Name, TraceId, ParentId, #{});
start_span(Name, TraceId) when is_integer(TraceId) andalso TraceId > 0->
    start_span(Name, TraceId, undefined, #{}).

-spec start_span(unicode:unicode_binary(), maybe(trace_context() | span()), map()) -> maybe(span()).
start_span(_Name, undefined, _) ->
    undefined;
start_span(Name, #trace_context{trace_id=TraceId,
                                span_id=ParentId}, Attributes) ->
    start_span(Name, TraceId, ParentId, Attributes);
start_span(Name, #span{trace_id=TraceId,
                       span_id=ParentId}, Attributes) ->
    start_span(Name, TraceId, ParentId, Attributes).

-spec start_span(unicode:unicode_binary(), maybe(trace_id()), maybe(span_id()), map()) -> maybe(span()).
start_span(_Name, undefined, undefined, _) ->
    undefined;
start_span(Name, TraceId, ParentId, Attributes) when is_integer(TraceId)
                                       , (is_integer(ParentId)
                                         orelse ParentId =:= undefined) ->
    #span{start_time = wts:timestamp(),
          trace_id = TraceId,
          span_id = generate_span_id(),
          parent_span_id = ParentId,
          name = Name,
          attributes = Attributes}.

%%--------------------------------------------------------------------
%% @doc
%% Finish a span, setting the end_time.
%% @end
%%--------------------------------------------------------------------
-spec finish_span(maybe(span())) -> maybe(span()).
finish_span(undefined) ->
    undefined;
finish_span(Span=#span{}) ->
    EndTime = wts:timestamp(),
    Span1 = Span#span{end_time = EndTime},
    _ = oc_reporter:store_span(Span1),
    Span1.

%%--------------------------------------------------------------------
%% @doc
%% Return the current trace context for a span, to be used for
%% propagation across process boundries.
%% @end
%%--------------------------------------------------------------------
context(undefined) ->
    undefined;
context(#span{trace_id=TraceId,
              span_id=SpanId}) ->
    #trace_context{trace_id=TraceId,
                   span_id=SpanId,
                   enabled=true}.
context(undefined, _) ->
  undefined;
context(#span{trace_id=TraceId,
              span_id=SpanId}, Enabled) ->
    #trace_context{trace_id=TraceId,
                   span_id=SpanId,
                   enabled=Enabled}.


%%--------------------------------------------------------------------
%% @doc
%% Put an attribute (a key/value pair) in the attribute map of a span.
%% If the attribute already exists it is overwritten with the new value.
%% @end
%%--------------------------------------------------------------------
-spec put_attribute(unicode:unicode_binary(), attribute_value(), maybe(span()))
                   -> maybe(span()) | {error, invalid_attribute}.
put_attribute(_Key, _Value, undefined) ->
    undefined;
put_attribute(Key, Value, Span=#span{attributes=Attributes}) ->
    Span#span{attributes=maps:put(Key, Value, Attributes)}.

%%--------------------------------------------------------------------
%% @doc
%% Merge a map of attributes with the current attributes of a span.
%% The new values overwrite the old if any keys are the same.
%% @end
%%--------------------------------------------------------------------
-spec put_attributes(#{unicode:unicode_binary() => attribute_value()}, maybe(span())) -> maybe(span()).
put_attributes(_NewAttributes, undefined) ->
    undefined;
put_attributes(NewAttributes, Span=#span{attributes=Attributes}) ->
    Span#span{attributes=maps:merge(Attributes, NewAttributes)}.

%%--------------------------------------------------------------------
%% @doc
%% Add an Annotation or MessageEvent to the list of TimeEvents in a span.
%%
%% @end
%%--------------------------------------------------------------------
-spec add_time_event(annotation() | message_event(), maybe(span())) -> maybe(span()).
add_time_event(TimeEvent, Span) ->
    add_time_event(wts:timestamp(), TimeEvent, Span).

-spec add_time_event(wts:timestamp(), annotation() | message_event(), maybe(span())) -> maybe(span()).
add_time_event(_Timestamp, _TimeEvent, undefined) ->
    undefined;
add_time_event(Timestamp, TimeEvent, Span=#span{time_events=TimeEvents}) ->
    Span#span{time_events=[{Timestamp, TimeEvent} | TimeEvents]}.

%%--------------------------------------------------------------------
%% @doc
%% Create an Annotation.
%% @end
%%--------------------------------------------------------------------
-spec annotation(unicode:unicode_binary(), attributes()) -> annotation().
annotation(Description, Attributes) ->
    #annotation{description=Description,
                attributes=Attributes}.

%%--------------------------------------------------------------------
%% @doc
%% Create a MessageEvent.
%% @end
%%--------------------------------------------------------------------
-spec message_event(message_event_type(), integer(), integer(), integer()) -> message_event().
message_event(MessageEventType, Id, UncompressedSize, CompressedSize) ->
    #message_event{type=MessageEventType,
                   id=Id,
                   uncompressed_size=UncompressedSize,
                   compressed_size=CompressedSize}.

%%--------------------------------------------------------------------
%% @doc
%% Set Status.
%% @end
%%--------------------------------------------------------------------
-spec set_status(integer(), unicode:unicode_binary(), maybe(span())) -> maybe(span()).
set_status(_Code, _Message, undefined) ->
    undefined;
set_status(Code, Message, Span) ->
    Span#span{status=#status{code=Code,
                             message=Message}}.

%%--------------------------------------------------------------------
%% @doc
%% Add a Link to the list of Links in the span.
%% @end
%%--------------------------------------------------------------------
-spec add_link(link(), maybe(span())) -> maybe(span()).
add_link(_Link, undefined) ->
    undefined;
add_link(Link, Span=#span{links=Links}) ->
    Span#span{links=[Link | Links]}.

%%--------------------------------------------------------------------
%% @doc
%% Create a Link which can be added to a Span.
%% @end
%%--------------------------------------------------------------------
-spec link(link_type(), trace_id(), span_id(), attributes()) -> link().
link(LinkType, TraceId, SpanId, Attributes) ->
    #link{type=LinkType,
          trace_id=TraceId,
          span_id=SpanId,
          attributes=Attributes}.

%%--------------------------------------------------------------------
%% @doc
%% Generates a 128 bit random integer to use as a trace id.
%% @end
%%--------------------------------------------------------------------
-spec generate_trace_id() -> trace_id().
generate_trace_id() ->
    uniform(2 bsl 127). %% 2 shifted left by 127 == 2 ^ 128

%%--------------------------------------------------------------------
%% @doc
%% Generates a 64 bit random integer to use as a span id.
%% @end
%%--------------------------------------------------------------------
-spec generate_span_id() -> span_id().
generate_span_id() ->
    uniform(2 bsl 63). %% 2 shifted left by 63 == 2 ^ 64

%%

%% Before OTP-20 rand:uniform could not give precision higher than 2^56.
%% Here we do a compile time check for support of this feature and will
%% combine multiple calls to rand if on an OTP version older than 20.0
-ifdef(high_bit_uniform).
uniform(X) ->
    rand:uniform(X).
-else.
-define(TWO_POW_56, 2 bsl 55).

uniform(X) when X =< ?TWO_POW_56 ->
    rand:uniform(X);
uniform(X) ->
    R = rand:uniform(?TWO_POW_56),
    (uniform(X bsr 56) bsl 56) + R.
-endif.
