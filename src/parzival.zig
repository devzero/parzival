const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const ComptimeStringMap = std.ComptimeStringMap;
//TODO implement "Rules" setting mechanism where you comptime register a set of Rules with Enum labels
//TODO implement memoization to prevent relooking for things
//TODO add additional recurser functions if necessary? maybe solve with Rule system?
//TODO figure out what's wrong with the predicates and why they get stuck in infinite loops
//TODO implement some sort of value stack with action functions for parsing? -- maybe not action tags might be sufficient?
//TODO use sequence arrays and choice arrays so grammars aren't as fugly -- blocking on zig issue #5579
//TODO don't use {}.f trick -- blocking on zig issue #1717
//TODO refactor Value type when you can include a value with an error -- blocking on zig issue #2647

pub const StatelessGrammar = Grammar(void, null);

pub fn Grammar(comptime State: type, rulesFunc: var) type {
    //represents a set of primitive parsing functions to create parsers from.  State is the data type used to store any state passed to a visitor object if they are called.
    return struct {
        pub const Self = @This();

        pub const ParserFn = fn (text: []const u8, visitor: ?Visitor) Value; //a Function prototype for all Parsing Functions (all parsing is composed from these)

        pub const LabelType = comptime []const u8;

        pub const RuleSet = if (rulesFunc) |theRulesFunc| {
            theRulesFunc(Self);
        } else {
            ComptimeStringMap(ParerFn, .{});
        };

        pub const Visitor = struct {
            state: *State,
            topVisitorFn: ?fn (state: *State, parser: usize) void = null,
            visitorFn: fn (state: *State, val: Value, parser: usize) void,
        };

        pub const Value = union(ValueType) {
            //This is returned by each parsing primitive, showing the result of a parse evalution
            Success: SuccessType, //When parser was successful`
            Failure: FailureType, //when parser failed

            pub inline fn success(text: []const u8, match_size: usize, labelval: ?LabelType, visitor: ?Visitor) Value {
                //helper function to create a successful Value
                const parser = @returnAddress();
                if (labelval) |theLabel| {
                    const val = Value{ .Success = SuccessType{ .matched = text[0..match_size], .rest = text[match_size..], .label = theLabel } };
                    if (visitor) |visitorStruct| {
                        visitorStruct.visitorFn(visitorStruct.state, val, parser);
                    }
                    return val;
                } else {
                    const val = Value{ .Success = SuccessType{ .matched = text[0..match_size], .rest = text[match_size..] } };
                    if (visitor) |visitorStruct| {
                        visitorStruct.visitorFn(visitorStruct.state, val, parser);
                    }
                    return val;
                }
            }
            pub inline fn failure(expected: []const u8, loc: [*]const u8, visitor: ?Visitor) Value {
                //helper function to create a failure Value
                const parser = @returnAddress();
                const val = Value{ .Failure = FailureType{ .expected = expected, .loc = loc } };
                if (visitor) |visitorStruct| {
                    visitorStruct.visitorFn(visitorStruct.state, val, parser);
                }
                return val;
            }

            pub inline fn isSuccess(v: Value) bool {
                //helper function to check to see whether Value is successful or failure
                return (@as(ValueType, v) == ValueType.Success);
            }
        };

        pub const ValueType = enum { Success, Failure }; //The enum tag for the Value union

        pub const SuccessType = struct {
            //represents what is returned from a successful match
            matched: []const u8 = &[_]u8{}, //a slice pointing to the original text data that matched
            rest: []const u8 = &[_]u8{}, //a slice pointing to the rest of the text buffer to be still parsed
            label: ?LabelType = null, //an optional annotation about the semantics of that matched text
        };

        pub const FailureType = struct {
            //represents what is returned from a failed match
            expected: []const u8 = &[_]u8{}, //a constant string describing the type of parsing failure that happened
            loc: [*]const u8, //a pointer to the beginning point of the failure in the original text
        };

        pub fn rule(comptime ruleName: []const u8) ParserFn {
            //represents a reference to another parsing rule by name
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    if (Self.RuleSet.get(ruleName)) |theParser| {
                        return theParser(text, visitor);
                    }
                    return Value.failure("rule: rule \"" ++ ruleName ++ "\" not found", text.ptr, visitor);
                }
            }.f;
        }

        pub fn label(labeltag: []const u8, comptime p: ParserFn) ParserFn {
            //Annotates positive results with an optional label that is retrievable when visiting
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    const res = p(text, visitor);
                    if (res.isSuccess()) {
                        return Value.success(text, res.Success.matched.len, labeltag, visitor);
                    }
                    return res;
                }
            }.f;
        }

        pub fn explain(explanation: []const u8, comptime p: ParserFn) ParserFn {
            //Overwrites the failure explanation with a more descriptive string for when this parser fails
            //TODO create function to wrap failure for this
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    const res = p(text, visitor);
                    if (!res.isSuccess()) {
                        return Value{ .Failure = FailureType{ .expected = explanation, .loc = res.Failure.loc } };
                    }
                    return res;
                }
            }.f;
        }

        pub fn char(comptime c: u8) ParserFn {
            //Terminal: accepts a specific constant character
            //have to use struct becuase https://github.com/ziglang/zig/issues/1717
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    if ((text.len > 0) and (text[0] == c)) {
                        return Value.success(text, 1, null, visitor);
                    } else {
                        return Value.failure("char '" ++ &[_]u8{c} ++ "'", text.ptr, visitor);
                    }
                }
            }.f;
        }

        pub fn charRange(comptime low: u8, comptime high: u8) ParserFn {
            comptime {
                if (low > high) {
                    @compileError("low must be less than high");
                }
            }
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    if (text.len < 1) {
                        return Value.failure("char range in '" ++ [_]u8{low} ++ "'-'" ++ [_]u8{high} ++ "' - no input", text.ptr, visitor);
                    }
                    if ((text.len > 0) and (text[0] >= low) and (text[0] <= high)) {
                        return Value.success(text, 1, null, visitor);
                    } else {
                        return Value.failure("char range in '" ++ [_]u8{low} ++ "'-'" ++ [_]u8{high} ++ "'", text.ptr, visitor);
                    }
                }
            }.f;
        }

        pub fn charSet(comptime cs: []const u8) ParserFn {
            //Terminal: accepts any character in string cs as one character (S+)
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    if (text.len < 1) {
                        return Value.failure("char in [" ++ cs ++ "] - no input", text.ptr, visitor);
                    }
                    inline for (cs) |c| {
                        if ((text.len > 1) and (text[0] == c)) {
                            return Value.success(text, 1, null, visitor);
                        }
                    }
                    return Value.failure("char in [" ++ cs ++ "]", text.ptr, visitor);
                }
            }.f;
        }

        pub fn charNotSet(comptime cs: []const u8) ParserFn {
            //Terminal: accepts any character not in string cs as one character (S+)
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    if (text.len < 1) {
                        return Value.failure("none of [" ++ cs ++ "] - no input", text.ptr, visitor);
                    }
                    inline for (cs) |c| {
                        if (text[0] == c) {
                            return Value.failure("none of [" ++ cs ++ "]", text.ptr, visitor);
                        }
                    }
                    return Value.success(text, 1, null, visitor);
                }
            }.f;
        }

        pub fn charAny(text: []const u8, visitor: ?Visitor) Value {
            //consumes any single character
            if (text.len > 0) {
                return Value.success(text, 1, null, visitor);
            } else {
                return Value.failure("any char", text.ptr, visitor);
            }
        }

        pub fn any(text: []const u8, visitor: ?Visitor) Value {
            //always matches and consumes no characters -- use of this is DANGEROUS and can lead to infinite loops
            return Value.success(text, 0, null, visitor);
        }

        pub fn rest(text: []const u8, visitor: ?Visitor) Value {
            //always matches and consumes all of the rest of the characters in the input string
            return Value.success(text, text.len, null, visitor);
        }

        pub fn fail(text: []const u8, visitor: ?Visitor) Value {
            //always fails immediately, consumes nothing
            return Value.failure("fail", text.prt, visitor);
        }

        pub fn string(comptime str: []const u8) ParserFn {
            //matches a specific comptime literal string
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    inline for (str) |c, i| {
                        if ((text.len < (i + 1)) or (text[i] != c)) {
                            return Value.failure("string \"" ++ str ++ "\"", text.ptr + i, visitor);
                        }
                    }
                    return Value.success(text, str.len, null, visitor);
                }
            }.f;
        }

        pub const space = comptime char(' ');

        pub const spaces = comptime oneOrMore(space);

        pub const digit = comptime charRange('0', '9');

        pub const digits = comptime oneOrMore(digit);

        pub const hexdigit = comptime choice(digit, choice(charRange('a', 'f'), charRange('A', 'F')));

        pub const hexdigits = comptime oneOrMore(hexdigit);

        pub const whiteSpaceChar = comptime charSet(" \n\r\t");

        pub const whiteSpace = comptime oneOrMore(whiteSpaceChar);

        pub const letter = comptime choice(charRange('A', 'Z'), charRange('a', 'z'));

        pub const letters = comptime oneOrMore(letter);

        pub const alphanum = comptime choice(letter, digit);

        pub fn choice(comptime a: ParserFn, comptime b: ParserFn) comptime ParserFn {
            // a / b in PEG notation - tries to match a, if that fails, goes back and tries to match b
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    const resA = a(text, visitor);
                    if (resA.isSuccess()) {
                        return resA;
                    } else {
                        return b(text, visitor);
                    }
                }
            }.f;
        }

        //pub fn choices(comptime parsers: var) -- equivalent to sequences() for choice, blocking on bug TODO

        pub fn sequence(comptime a: ParserFn, comptime b: ParserFn) comptime ParserFn {
            // tries to match a and b in order
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    const resA = a(text, visitor);
                    if (resA.isSuccess()) {
                        const resB = b(resA.Success.rest, visitor);
                        if (resB.isSuccess()) {
                            const matchedLen = resA.Success.matched.len + resB.Success.matched.len;
                            return Value.success(text, matchedLen, null, visitor);
                        } else {
                            return resB;
                        }
                    } else {
                        return resA;
                    }
                }
            }.f;
        }

        pub fn recurserMany(comptime pre: ParserFn, comptime alternatives: ParserFn, comptime post: ParserFn, comptime labelName: []const u8) comptime ParserFn {
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    std.debug.warn("--fn start\n", .{});
                    var matchedLen: usize = 0;
                    const preRes = pre(text, visitor);
                    std.debug.warn("---parsed pre\n", .{});
                    if (!preRes.isSuccess()) {
                        return preRes;
                    }
                    var restOfText = preRes.Success.rest;
                    matchedLen += preRes.Success.matched.len;
                    var altRes = preRes;
                    while (altRes.isSuccess()) {
                        altRes = alternatives(restOfText, visitor);
                        if (!altRes.isSuccess()) {
                            const nextLevel = recurserMany(pre, alternatives, post, labelName);
                            altRes = nextLevel(restOfText, visitor);
                        }
                        if (altRes.isSuccess()) {
                            restOfText = altRes.Success.rest;
                            matchedLen += altRes.Success.matched.len;
                        }
                    }
                    const postRes = post(restOfText, visitor);
                    if (postRes.isSuccess()) {
                        return Value.success(text, matchedLen + postRes.Success.matched.len, null, visitor);
                    }
                    return postRes;
                }
            }.f;
        }

        // NOT WORKING YET DUE TO BUG https://github.com/ziglang/zig/issues/5579
        //pub fn sequences(comptime parsers: var) comptime ParserFn {
        //    for (std.meta.fields(@TypeOf(parsers))) |fieldInfo| {
        //        if (fieldInfo.field_type != ParserFn) {
        //            @compileError("Arguments must be ParserFns");
        //        }
        //    }
        //    return struct {
        //        pub fn f(text: []const u8, visitor: ?Visitor) Value {
        //            var lastRes = parsers.@"0"(text, visitor);
        //            var matchedLen: usize = 0;
        //            inline for (std.meta.fields(@TypeOf(parsers))) |parserField| {
        //                const parser = @field(parsers, parserField.name);
        //                lastRes = parser(text, visitor);
        //                if (lastRes.isSuccess()) {
        //                    matchedLen += lastRes.Success.matched.len;
        //                } else {
        //                    return Value.success(text, matchedLen, null, visitor);
        //                }
        //            }
        //            return Value.success(text, matchedLen, null, visitor);
        //        }
        //    }.f;
        //}

        pub fn optional(comptime p: ParserFn) comptime ParserFn {
            //will match zero or one instance of p
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    const res = p(text, visitor);
                    if (res.isSuccess()) {
                        return res;
                    } else {
                        return Value.success(text, 0, null, visitor);
                    }
                }
            }.f;
        }

        pub fn many(comptime p: ParserFn) comptime ParserFn {
            //will match zero or more instances of p
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    var res = p(text, visitor);
                    var depth: usize = 0;
                    while (res.isSuccess()) {
                        depth += res.Success.matched.len;
                        res = p(text[depth..], visitor);
                    }
                    return Value.success(text, depth, null, visitor);
                }
            }.f;
        }

        pub fn times(comptime p: ParserFn, minT: ?comptime_int, maxT: ?comptime_int) ParserFn {
            //will match p occuring more than minT times but less than maxT times if specified
            comptime {
                if (minT) |min| {
                    if (maxT) |max| {
                        if (max < min) {
                            @compileError("min times must be less than or equal to max times");
                        }
                    }
                }
            }
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    var res = p(text, visitor);
                    var iters: usize = 0;
                    var depth: usize = 0;
                    const min = minT orelse 0;
                    while (true) : (iters += 1) {
                        if (maxT) |max| {
                            if (iters > max) {
                                return Value.failure("times()", text.ptr, visitor);
                            }
                        }
                        if (!res.isSuccess()) {
                            if (min > iters) {
                                return res;
                            } else {
                                return Value.success(text, depth, null, visitor);
                            }
                        }
                        depth += res.Success.matched.len;
                        res = p(text, state[depth..], visitor);
                    }
                }
            }.f;
        }

        pub fn oneOrMore(comptime p: ParserFn) comptime ParserFn {
            //matches one or more instance of p
            return comptime sequence(p, many(p));
        }

        pub fn andPredicate(comptime p: ParserFn) comptime ParserFn {
            // &p in PEG notation - tries to match p and succeeds iff p does, but never consumes text
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    const res = p(text, visitor);
                    if (res.isSuccess()) {
                        return Value.success(text, 0, null, visitor);
                    } else {
                        return res;
                    }
                }
            }.f;
        }

        pub fn notPredicate(comptime p: ParserFn) comptime ParserFn {
            // &p in PEG notation - tries to match p and succeeds iff p does not, but never consumes text
            return struct {
                pub fn f(text: []const u8, visitor: ?Visitor) Value {
                    const res = p(text, visitor);
                    if (res.isSuccess()) {
                        return Value.failure("not predicate", text.ptr, visitor);
                    } else {
                        return Value.success(text, 0, null, visitor);
                    }
                }
            }.f;
        }
    };
}

pub fn match(parser: StatelessGrammar.ParserFn, text: []const u8) bool {
    //returns true iff the provided stateless parser matches text
    return parser(text, null).isSuccess();
}

pub fn debugMatch(comptime grammar: type, parser: var, text: []const u8) bool {
    //returns true iff the provided Grammar parser matches text and prints verbose callback information to undestand how it is parsing
    comptime {
        if (@TypeOf(parser) != grammar.ParserFn) {
            @compileError("Type mismatch between grammar and parser type");
        }
    }
    var textStart: usize = @ptrToInt(text.ptr);
    const visitorFn = struct {
        pub fn f(state: *usize, val: grammar.Value, parserAddr: usize) void {
            if (val.isSuccess()) {
                if (val.Success.label) |aLabel| {
                    std.debug.warn("MATCH: [{}] ({}) !<{}> \"{}\"\n", .{ @ptrToInt(val.Success.matched.ptr) - state.*, aLabel, parserAddr, val.Success.matched });
                } else {
                    std.debug.warn("MATCH: [{}] ({})  \"{}\"\n", .{ @ptrToInt(val.Success.matched.ptr) - state.*, parserAddr, val.Success.matched });
                }
            } else {
                std.debug.warn("FAIL: [{}] ({}) '{c}'-> \"{}\"\n", .{ @ptrToInt(val.Failure.loc) - state.*, parserAddr, val.Failure.loc[0], val.Failure.expected });
            }
        }
    }.f;
    return parser(text, grammar.Visitor{ .state = &textStart, .visitorFn = visitorFn }).isSuccess();
}

const Matcher = struct {
    //a type that stores all matches as they happen and provides a hashmap to lookup all matches of a given label
    arena: *ArenaAllocator,
    allocator: *Allocator,
    grammar: GrammarType.ParserFn,
    matches: ?[][]const u8 = null,
    labels: ?StringHashMap([][]const u8) = null,
    lastError: ?[]const u8 = null,

    const MatcherState = struct {
        allocator: *Allocator,
        labelDict: *StringHashMap(ArrayList([]const u8)),
        matches: *ArrayList([]const u8),

        pub fn init(allocator: *Allocator) !MatcherState {
            var hm = try allocator.create(StringHashMap(ArrayList([]const u8)));
            hm.* = StringHashMap(ArrayList([]const u8)).init(allocator);
            var mt = try allocator.create(ArrayList([]const u8));
            mt.* = ArrayList([]const u8).init(allocator);
            return MatcherState{
                .allocator = allocator,
                .labelDict = hm,
                .matches = mt,
            };
        }

        pub fn toOwned(self: *MatcherState, matcher: *Matcher) !void {
            matcher.matches = self.matches.toOwnedSlice();
            matcher.labels = StringHashMap([][]const u8).init(matcher.allocator);
            var iterator = self.labelDict.iterator();
            while (iterator.next()) |item| {
                _ = try matcher.labels.?.put(item.key, item.value.toOwnedSlice());
            }
            self.labelDict.clear();
        }

        pub fn deinit(self: *MatcherState) void {
            var iterator = self.labelDict.iterator();
            while (iterator.next()) |item| {
                _ = item.value.deinit();
            }
            self.labelDict.deinit();
            self.allocator.destroy(self.labelDict);
            self.matches.deinit();
            self.allocator.destroy(self.matches);
        }
    };

    pub const GrammarType = Grammar(MatcherState);

    pub fn init(allocator: *Allocator, comptime grammar: Matcher.GrammarType.ParserFn) !*Matcher {
        var arena = try allocator.create(ArenaAllocator);
        arena.* = ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        var self = try arena.allocator.create(Matcher);
        self.* = Matcher{
            .allocator = &arena.allocator,
            .arena = arena,
            .grammar = grammar,
        };
        return self;
    }

    pub fn deinit(self: *Matcher) void {
        var arena = self.arena;
        var allocator = self.arena.child_allocator;
        arena.deinit();
        allocator.destroy(arena);
    }

    pub fn matchVisitor(state: *MatcherState, val: Matcher.GrammarType.Value, parser: usize) void {
        if (val.isSuccess()) {
            std.debug.warn("MATCH: {}\n", .{val.Success.matched});
            state.matches.append(val.Success.matched) catch return;
            if (val.Success.label) |theLabel| {
                if (state.labelDict.get(theLabel)) |labelList| {
                    labelList.value.append(val.Success.matched) catch return;
                } else {
                    var newAL = state.allocator.create(ArrayList([]const u8)) catch return;
                    newAL.* = ArrayList([]const u8).init(state.allocator);
                    newAL.append(val.Success.matched) catch return;
                    _ = state.labelDict.put(theLabel, newAL.*) catch return;
                }
            }
        }
    }

    pub fn match(self: *Matcher, text: []const u8) !bool {
        var state: MatcherState = try MatcherState.init(self.allocator);
        defer state.deinit();
        var res = self.grammar(text, Matcher.GrammarType.Visitor{ .state = &state, .visitorFn = Matcher.matchVisitor });
        if (res.isSuccess()) {
            try state.toOwned(self);
            return true;
        } else {
            self.lastError = res.Failure.expected;
            return false;
        }
    }
};
