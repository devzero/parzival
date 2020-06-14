const std = @import("std");
const testing = std.testing;
const parzival = @import("parzival.zig");

usingnamespace parzival;

test "match" {
    const g = StatelessGrammar;
    const parser = comptime g.sequence(g.spaces, g.letters);
    testing.expect(match(parser, "  abcd"));
}

test "debugMatch" {
    const G = Grammar(usize, null);
    const parser = comptime G.oneOrMore(G.sequence(G.spaces, G.label("words", G.letters)));
    std.debug.warn("\n", .{});
    testing.expect(debugMatch(G, parser, " ab cd efg"));
}

pub fn mkRules(comptime G: type) var {
    const rules = .{
        .{ "", G.sequence(G.rule("A"), G.rule("B")) },
        .{ "A", G.spaces },
        .{ "B", G.letters },
    };
    return std.ComptimeStringMap(g.ParserFn, rules);
}

test "rules" {
    const optMkRules: ?@TypeOf(mkRules) = mkRules;
    const G = Grammar(usize, optMkRules);
    testing.expect(match(G.rule(""), "   abcd"));
}

//test "matches" {
//    const g = parzival.Matcher.GrammarType;
//    const grammar = comptime g.oneOrMore(g.sequence(g.spaces, g.label("words", g.letters)));
//    var m = try Matcher.init(testing.allocator, grammar);
//    defer m.deinit();
//    var input = "  a b cd efg";
//    testing.expect(try m.match(input));
//    std.debug.warn("\nmatches:\n", .{});
//    if (m.matches) |matches| {
//        for (matches) |aMatch| {
//            std.debug.warn("  \"{}\"\n", .{aMatch});
//        }
//    }
//    std.debug.warn("\nlabels:\n", .{});
//    if (m.labels) |labels| {
//        var iterator = labels.iterator();
//        while (iterator.next()) |item| {
//            std.debug.warn("  \"{}\":\"[", .{item.key});
//            for (item.value) |s| {
//                std.debug.warn(" \"{}\",", .{s});
//            }
//            std.debug.warn("]\n", .{});
//        }
//    }
//}
