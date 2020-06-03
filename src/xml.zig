const std = @import("std");
const parzival = @import("parzival.zig");
const testing = std.testing;
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;

pub const Node = struct {
    const NodeType = enum { rootNode, elementNode, textNode, commentNode, processingInstructionNode, cdataNode, docTypeNode };
    nodeType: NodeType,
    allocator: *Allocator,
    parent: ?*Node,
    nodes: []*Node,
    nodesByTag: StringHashMap(ArrayList(*Node)),
    attrib: StringHashMap([]const u8),
    tag: []const u8,
    text: []const u8,

    pub fn init(allocator: *Allocator, data: []const u8) ParseErrors!*Node {
        var self = try allocator.create(Node);
        self.nodeType = .rootNode;
        self.allocator = allocator;
        self.parent = null;
        self.nodes = &[_]*Node{};
        self.nodesByTag = StringHashMap(ArrayList(*Node)).init(self.allocator);
        self.attrib = StringHashMap([]const u8).init(self.allocator);
        self.tag = &[_]u8{};
        self.text = &[_]u8{};
        var size = try self.parse(data);
        if (size < data.len) {
            return error.ParsingError; //didn't parse the whole document?
        }
        return self;
    }
    pub fn initChild(parent: *Node, nodeType: NodeType) !*Node {
        var self = try parent.allocator.create(Node);
        self.nodeType = nodeType;
        self.allocator = parent.allocator;
        self.parent = parent;
        self.nodes = &[_]*Node{};
        self.nodesByTag = StringHashMap(ArrayList(*Node)).init(self.allocator);
        self.attrib = StringHashMap([]const u8).init(self.allocator);
        self.tag = &[_]u8{};
        self.text = &[_]u8{};
        return self;
    }

    const States = enum {
        startState, charData, startStateElem, bangThing, commentState, processingInstr, docType, cdataState, tagName, tagWhitespace, attribName, attribEq, attribValue, selfEndTag, contentsState, endTag, endState
    };
};

const XMLState = struct {
    //Nodes
};

const XMLParser = struct {};

const XMLGrammar = parzival.Grammar(XMLState);

const DOCUMENT = comptime label("DOCUMENT", sequence(PROLOG, sequence(ELEMENT, sequence(oneOrMore(MISC)))));
const PROLOG = comptime label("PROLOG", sequence(XMLDECL, sequence(many(MISC), optional(sequence(DOCTYPEDECL, many(MISC))))));
const XMLDECL = comptime label("XMLDECL", sequence(string("<?xml"), sequence(VERSIONINFO, sequence(optional(ENCODINGDECL), sequence(optional(SDDECL), sequence(optional(S), string("?>")))))));
const VERSIONINFO = comptime label("VERSIONINFO", sequence(S, sequence(string("version"), sequence(EQ, choice(sequence(string("\""), sequence(VERSIONNUM, string("\""))), sequence(string("'"), sequence(VERSIONNUM, string("'"))))))));
const EQ = comptime label("EQ", sequence(optional(S), sequence(char('='), optional(S))));
const VERSIONNUM = comptime label("VERSIONNUM", choice(string("1.1"), string("1.0")));
const MISC = comptime label("MISC", choice(COMMENT, choice(PI, S)));
const DOCTYPEDECL = comptime label("DOCTYPEDECL", sequence(string("<!DOCTYPE"), sequence(S, sequence(NAME, sequence(optional(sequence(S, EXTERNALID)), sequence(optional(S), sequence(optional(sequence(char('['), sequence(INTSUBSET, sequence(char(']'), optional(S))))), string("?>"))))))));
const ENCODINGDECL = comptime label("ENCODINGDECL", sequence(S, sequence(string("encoding"), sequence(EQ, choice(sequence(char('"'), sequence(ENCNAME, char('"'))), sequence(char('\''), sequence(ENCNAME, char('\''))))))));
const ENCNAME = comptime label("ENCNAME", sequence(letter, many(choice(alphanum, charSet("._")))));
const SDDECL = comptime label("SDDECL", sequence(S, sequence(string("standalone"), sequence(EQ, choice(sequence(char('"'), sequence(choice(string("yes"), string("no")), char('"'))), sequence(char('\''), sequence(choice(string("yes"), string("no")), char('\''))))))));
const COMMENT = comptime label("COMMENT", sequence(string("<!--"), sequence(many(choice(charNotSet("-"), sequence(char('-'), charNotSet("-")))), string("-->"))));
const S = comptime label("S", whiteSpace);
const NAME = comptime label("NAME", sequence(NAMESTARTCHAR, many(NAMECHAR)));
const NAMESTARTCHAR = comptime label("NAMESTARCHAR", choice(charSet(":_"), letter));
const NAMECHAR = comptime label("NAMECHAR", choice(NAMESTARTCHAR, choice(charSet("-."), digit)));

const NAMES = comptime label("NAMES", sequence(NAME, optional(sequence(char(' '), NAME))));
const NMTOKEN = comptime label("NAMETOKEN", oneOrMore(NAMECHAR));
const NMTOKENS = comptime label("NAMETOKENS", sequence(name, optional(sequence(char(' '), NAMETOKEN))));
const EXTERNALID = comptime label("EXTERNALID", choice(sequence(string("SYSTEM"), sequence(S, SYSTEMLITERAL)), sequence(string("PUBLIC"), sequence(S, sequence(PUBIDLITERAL, sequence(S, SYSTEMLITERAL))))));
const SYSTEMLITERAL = comptime label("SYSTEMLITERAL", choice(sequence(char('"'), sequence(many(charNotSet("\"")), char('"'))), sequence(char('\''), sequence(many(charNotSet("'")), char('\'')))));
const PUBIDLITERAL = comptime label("PUBIDLITERAL", choice(sequence(char('"'), sequence(many(PUBIDCHAR), char('"'))), sequence(char('\''), sequence(many(PUBIDCHARN), char('\'')))));
const PUBIDCHARN = comptime label("PUBIDCHAR", choice(charSet("\x20\r\n-()+,./:=?;!*#@$%_"), alphanum));
const PUBIDCHAR = comptime label("PUBIDCHAR", choice(PUBIDCHARN, char('\'')));
const INTSUBSET = comptime label("INTSUBSET", many(choice(DECLSEP, MARKUPDECL)));
const DECLSEP = comptime label("DECLSEP", choice(S, PEREFERENCE));
const PEREFERENCE = comptime label("PEREFERENCE", sequence(char('%'), sequence(NAME, char(';'))));
const MARKUPDECL = comptime label("MARKUPDECL", choice(ELEMENTDECL, choice(ATTLISTDECL, choice(ENTITYDECL, choice(NOTATIONDECL, choice(PI, COMMENT))))));
const ELEMENTDECL = comptime label("ELEMENTDECL", sequence(string("<!ELEMENT"), sequence(S, sequence(NAME, sequence(S, sequence(CONTENTSPEC, sequence(optional(S), string("?>"))))))));
const CONTENTSPEC = comptime label("CONTENTSPEC", choice(string("EMPTY"), choice(string("ANY"), choice(MIXED, CHILDREN))));
const MIXED = comptime label("MIXED", choice(sequence(char('('), sequence(optional(S), sequence(string("#PCDATA"), sequence(many(sequence(optional(S), sequence(char('|'), sequence(optional(S), NAME)))), sequence(optional(S), string(")*")))))), sequence(char('('), sequence(optional(S), sequence(string("#PCDATA"), sequence(optional(S), char(')')))))));
const CHILDREN = comptime label("CHILDREN", sequence(choice(CHOICE, SEQ), optional(choice(char('?'), choice(char('*'), char('+'))))));
const CHOICE = comptime label("CHOICE", sequence(char('('), sequence(optional(S), sequence(CP, sequence(oneOrMore(sequence(optional(S), sequence(char('|'), sequence(optional(S), CP)))), sequence(optional(S), char(')')))))));
//const CP = comptime label("CP", sequence(choice(NAME, choice(CHOICE, SEQ)), optional(choice(char('*'), choice(char('+'), char('?'))))));
const CP = comptime label("CP", sequence(NAME, optional(choice(char('*'), choice(char('+'), char('?')))))); //intentionally not allowing nested choice/seqs because they cause a loop in the grammar
const SEQ = comptime label("SEQ", sequence(char('('), sequence(optional(S), sequence(CP, sequence(oneOrMore(sequence(optional(S), sequence(char(','), sequence(optional(S), CP)))), sequence(optional(S), char(')')))))));
const ATTLISTDECL = comptime label("ATTLISTDECL", sequence(string("<!ATTLIST"), sequence(S, sequence(NAME, sequence(many(ATTDEF), sequence(S, char('>')))))));
const ATTDEF = comptime label("ATTDEF", sequence(S, sequence(NAME, sequence(ATTTYPE, sequence(S, DEFAULTDECL)))));
const ATTTYPE = comptime label("ATTTYPE", choice(STRINGTYPE, choice(TOKENIZEDTYPE, ENUMERATEDTYPE)));
const STRINGTYPE = comptime label("STRINGTYPE", string("CDATA"));
const TOKENIZEDTYPE = comptime label("TOKENIZEDTYPE", choice(string("IDREFS"), choice(string("IDREF"), choice(string("ID"), choice(string("ENTITIES"), choice(string("ENTITY"), choice(string("NMTOKENS"), string("NMTOKEN"))))))));
const ENUMERATEDTYPE = comptime label("ENUMERATEDTYPE", choice(NOTATIONTYPE, ENUMERATION));
const NOTATIONTYPE = comptime label("NOTATIONTYPE", sequence(string("NOTATION"), sequence(S, sequence(char('('), sequence(optional(S), sequence(NAME, sequence(optional(sequence(optional(S), sequence(char('|'), sequence(optional(S), NAME)))), sequence(optional(S), char(')')))))))));
const ENUMERATION = comptime label("ENUMERATION", sequence(char('('), sequence(optional(S), sequence(NMTOKEN, sequence(many(sequence(optional(S), sequence(char('|'), sequence(optional(S), NMTOKEN)))), sequence(optional(S), char(')')))))));
const ENTITYDECL = comptime label("ENTITYDECL", choice(GEDECL, PEDECL));
const GEDECL = comptime label("GEDECL", sequence(string("<!ENTITY"), sequence(S, sequence(NAME, sequence(S, sequence(ENTITYDEF, sequence(optional(S), char('>'))))))));
const ENTITYDEF = comptime label("ENTITYDEF", choice(ENTITYVALUE, sequence(EXTERNALID, optional(NDATADECL))));
const ENTITYVALUE = comptime label("ENTITYVALUE", choice(sequence(char('"'), sequence(many(choice(charNotSet("%&"), choice(PEREFERENCE, REFERENCE))), char('"'))), sequence(char('\''), sequence(many(choice(charNotSet("%&"), choice(PEREFERENCE, REFERENCE))), char('\'')))));
const PEDECL = comptime label("PEDECL", sequence(string("<!ENTITY"), sequence(S, sequence(char('%'), sequence(S, sequence(NAME, sequence(S, sequence(PEDEF, sequence(optional(S), char('>'))))))))));
const PEDEF = comptime label("PEDEF", choice(ENTITYVALUE, EXTERNALID));
const NDATADECL = comptime label("NDATADECL", sequence(S, sequence(string("NDATA"), sequence(S, NAME))));
const NOTATIONDECL = comptime label("NOTATIONDECL", sequence(string("<!NOTATION"), sequence(S, sequence(NAME, sequence(S, sequence(choice(EXTERNALID, PUBLICID), sequence(optional(S), char('>'))))))));
const PUBLICID = comptime label("PUBLICID", sequence(string("PUBLIC"), sequence(S, PUBIDLITERAL)));
const DEFAULTDECL = comptime label("DEFAULTDECL", choice(string("#REQUIRED"), choice(string("#IMPLIED"), sequence(optional(sequence(string("#FIXED"), S)), ATTVALUE))));
const PI = comptime label("PI", sequence(string("<?"), sequence(PITARGET, sequence(S, sequence(many(charNotSet("?>")), string("?>"))))));
const PITARGET = comptime label("PITARGET", sequence(notPredicate(sequence(charSet("Xx"), sequence(charSet("Mm"), charSet("Ll")))), NAME));
const ELEMENT = comptime label("ELEMENT", choice(EMPTYELEMTAG, sequence(STAG, CONTENT, ETAG)));
const EMPTYELEMTAG = comptime label("EMPTELEMTAG", sequence(char('<'), sequence(NAME, sequence(many(sequence(S, ATTRIBUTE)), sequence(optional(S), string("/>"))))));
const ATTRIBUTE = comptime label("ATTRIBUTE", sequence(NAME, sequence(EQ, ATTVALUE)));
const ATTVALUE = comptime label("ATTVALUE", choice(sequence(char('"'), sequence(many(choice(PEREFERENCE, choice(REFERENCE, charNotSet("<&\"")))), char('"'))), sequence(char('\''), sequence(many(choice(PEREFERENCE, choice(REFERENCE, charNotSet("<&\"")))), char('\'')))));
const REFERENCE = comptime label("REFERENCE", choice(ENTITYREF, CHARREF));
const ENTITYREF = comptime label("ENTITYREF", sequence(char('&'), sequence(NAME, char(';'))));
const CHARREF = comptime label("CHARREF", choice(sequence(string("&#"), sequence(digits, char(';'))), sequence(string("&#x"), sequence(hexdigits, char(';')))));
const STAG = comptime label("STAG", sequence(char('<'), sequence(NAME, sequence(many(sequence(S, ATTRIBUTE)), sequence(optional(S), char('>'))))));
const ETAG = comptime label("ETAG", sequence(string("</"), sequence(NAME, sequence(optional(S), char('>')))));
const CONTENT = comptime label("CONTENT", sequence(optional(CHARDATA), sequence(many(choice(ELEMENT, choice(REFERENCE, choice(CDSECT, choice(PI, COMMENT))))), optional(CHARDATA))));
const CHARDATA = comptime label("CHARDATA", many(sequence(many(charNotSet("[<&")), sequence(notPredicate(string("]]>")), many(charNotSet("[<&")))))); //not sure about this one
const CDSECT = comptime label("CDSECT", sequence(CDSTART, sequence(CDATA, CDEND)));
const CDSTART = comptime label("CDSTART", string("<!CDATA["));
const CDATA = comptime label("CDATA", many(sequence(charNotSet(']'), sequence(notPedicate(string("]]"), any))))); //not sure about this one
const CDEND = comptime label("CDEND", string("]]>"));

usingnamespace XMLGrammar;

test "foo" {
    testing.expect(DOCUMENT("<element/>", null).isSuccess());
}
