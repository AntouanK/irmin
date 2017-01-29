(*
 * Copyright (c) 2013-2017 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

(** Merge operators. *)

open Result

type conflict = [ `Conflict of string ]

type 'a promise = unit -> ('a option, conflict) result Lwt.t

type 'a f = old:'a promise -> 'a -> 'a -> ('a, conflict) result Lwt.t
type 'a t
val v: 'a Depyt.t -> 'a f -> 'a t
val f: 'a t -> 'a f

val promise: 'a -> 'a promise
val promise_map: ('a -> 'b) -> 'a promise -> 'b promise
val promise_bind: 'a promise -> ('a -> 'b promise) -> 'b promise

val seq: 'a t list -> 'a t
val default: 'a Depyt.t -> 'a t

val unit: unit t
val bool: bool t
val char: char t
val int: int t
val int32: int32 t
val int64: int64 t
val float: float t
val string: string t

type counter = int
val counter: counter t

val option: 'a t -> 'a option t
val pair:  'a t -> 'b t -> ('a * 'b) t
val triple: 'a t -> 'b t -> 'c t -> ('a * 'b * 'c) t

module MultiSet (K: sig include Set.OrderedType val t: t Depyt.t end):
sig
  val merge: counter Map.Make(K).t t
end

module Set (E: sig include Set.OrderedType val t: t Depyt.t end):
sig
  val merge: Set.Make(E).t t
end

val alist: 'a Depyt.t -> 'b Depyt.t -> ('a -> 'b option t) -> ('a * 'b) list t

module Map (K: sig include Map.OrderedType val t: t Depyt.t end):
sig
  val merge: 'a Depyt.t -> (K.t -> 'a option t) -> 'a Map.Make(K).t t
end

val like: 'a Depyt.t -> 'b t -> ('a -> 'b) -> ('b -> 'a) -> 'a t
val like_lwt: 'a Depyt.t -> 'b t -> ('a -> 'b Lwt.t) -> ('b -> 'a Lwt.t) -> 'a t

val with_conflict: (string -> string) -> 'a t -> 'a t

val ok: 'a -> ('a, conflict) result Lwt.t
val conflict: ('a, unit, string, ('b, conflict) result Lwt.t) format4 -> 'a

module Infix: sig
  val (>>|):
    ('a, conflict) result Lwt.t ->
    ('a -> ('b, conflict) result Lwt.t) ->
    ('b, conflict) result Lwt.t
  val (>?|): 'a promise -> ('a -> 'b promise) -> 'b promise
end

val conflict_t: conflict Depyt.t
val result_t: 'a Depyt.t -> ('a, conflict) result Depyt.t
