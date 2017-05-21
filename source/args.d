import args;

import std.container.array : Array;
import std.array : empty, front;
import std.stdio;

bool parseArgs(Opt,Args)(ref Opt opt, ref Args args) 
{
	return parseArgs!("--", "-")(opt, "", args);
}

struct ConfigFile {
	@Arg() string config;
	@Arg() string genConfig;
}

bool parseArgsWithConfigFile(Opt,Args)(ref Opt opt, ref Args args) {
	ConfigFile cf;
	bool helpWanted = parseArgs(cf, args);

	if(!cf.genConfig.empty) {
		writeConfigToFile(cf.genConfig, opt);
	}

	if(!cf.config.empty) {
		auto fromFile = parseArgsConfigFile(cf.config);
		parseConfigFile(opt, fromFile);
	}

	bool tmp = parseArgs(opt, args);
	return tmp || helpWanted;
}

unittest {
	import std.format : format;

	static struct Embed {
		@Arg() int b = 2;
	}

	static struct Options {
		@Arg() int a = 1;
		@Arg() Embed embed;
	}

	{
		Options options;
		auto args = ["funcname", "--genConfig", "configfile.argsd"];
		assert(!parseArgsWithConfigFile(options, args));
	}
	{
		Options options;
		options.a = 20;
		options.embed.b = 30;
		auto args = ["funcname", "--config", "configfile.argsd"];
		assert(!parseArgsWithConfigFile(options, args));
		assert(options.a == 1, format("%s", options.a));
		assert(options.embed.b == 2);
	}
}

void writeConfigToFile(Opt)(string filename, ref Opt opt) {
	import std.stdio : File;
	auto f = File(filename, "w");
	auto ltw = f.lockingTextWriter();
	writeConfigToFileImpl(opt, ltw, "");
}

void writeConfigToFileImpl(Opt,LTW)(ref Opt opt, ref LTW ltw, string prefix) {
	import std.traits : hasUDA, getUDAs, Unqual;
	import std.format : formattedWrite;		
	foreach(mem; __traits(allMembers, Opt)) {
		static if(hasUDA!(__traits(getMember, opt, mem), Argument)) {
			Argument optMemArg = getUDAs!(
					__traits(getMember, opt, mem), Argument
				)[0];
			static if(is(typeof(__traits(getMember, Opt, mem)) == struct)) {
				writeConfigToFileImpl(__traits(getMember, opt, mem), 
						ltw, mem ~ ".");
			} else {
				printHelpMessageConfig!(typeof(__traits(getMember, Opt, mem)))(
						ltw, optMemArg
					);
				formattedWrite(ltw, "%s%s = \"%s\"\n",
						prefix, mem, __traits(getMember, opt, mem)
					);
			}
		}
	}
}

void printHelpMessageConfig(Type,LTW)(ref LTW ltw, ref const(Argument) arg) {
	import std.format : formattedWrite;
	import std.traits : Unqual;

	formattedWrite(ltw, "\n# ");
	foreach(dchar it; arg.helpMessage) {
		if(it == '\n' || it == '\t') {
			formattedWrite(ltw, "%s", ' ');
			continue;
		} else {
			formattedWrite(ltw, "%s", it);
		}
	}

	formattedWrite(ltw, "\n# Type: %s\n", Type.stringof);
}

Array!string parseArgsConfigFile(string filename) {
	import std.file : readText;
	import std.algorithm.iteration : splitter;
	import std.algorithm.searching : startsWith;
	import std.algorithm.mutation : strip;
	import std.string : indexOf;

	Array!string ret;
	ret.insertBack("dummyBecauseTheFirstArgumentIsTheFileName");

	auto file = readText(filename);
	foreach(line; file.splitter('\n')) {
		if(line.startsWith('#')) {
			continue;
		}

		ptrdiff_t eq = line.indexOf('=');
		if(eq == -1) {
			continue;
		}

		ret.insertBack(line[0 .. eq].strip(' ').strip('"'));
		ret.insertBack(line[eq+1 .. $].strip(' ').strip('"'));
	}

	return ret;
}

void parseConfigFile(Opt,Args)(ref Opt opt, ref Args args) {
	parseArgs!("", "")(opt, "", args);
}

enum Optional {
	yes,
	no
}

struct Argument {
	bool isArgument = false;
	string helpMessage;
	char shortName = '\0';
	Optional optional = Optional.yes;

	this(T...)(T args) {
		static if(T.length > 0) {
			this.isArgument = true;
			construct(0, args);
		}
	}

	void construct(T...)(T args) {
		import std.traits : isSomeString, isSomeChar;
		static if(isSomeString!(T[0])) {
			this.helpMessage = args[0];
		} else static if(isSomeChar!(T[0])) {
			this.shortName = args[0];
		} else static if(is(T[0] == Optional)) {
			this.optional = args[0];
		}

		static if(T.length > 1) {
			construct(args[1 .. $]);
		}
	}
}

Argument Arg(T...)(T args) {
	return Argument(args);
}

Argument getArgs(alias T)() {
	import std.traits : hasUDA, getUDAs;
	static if(hasUDA!(T, Argument)) {
		return Argument(getUDAs!(T, Argument)[0].helpMessage, 
				getUDAs!(T, Argument)[0].shortName,
				getUDAs!(T, Argument)[0].optional);
	} else {
		return Argument();
	}
}

unittest {
	@Arg() int a;
	Argument arg = getArgs!(a);
	assert(arg.shortName == '\0');
	assert(arg.helpMessage == "");
	assert(arg.optional == Optional.yes);

	@Arg("", 'b') int b;
	Argument arg2 = getArgs!(b);
	assert(arg2.shortName == 'b');
	assert(arg2.helpMessage == "");
	assert(arg2.optional == Optional.yes);

	@Arg("helpMe", 'b') int c;
	Argument arg3 = getArgs!(c);
	assert(arg3.shortName == 'b');
	assert(arg3.helpMessage == "helpMe");
	assert(arg3.optional == Optional.yes);

	@Arg("helpMe", 'b') int d;
	Argument arg4 = getArgs!(d);
	assert(arg4.shortName == 'b');
	assert(arg4.helpMessage == "helpMe");
	assert(arg4.optional == Optional.yes);

	@Arg("helpMe", 'b', Optional.no) int e;
	Argument arg5 = getArgs!(e);
	assert(arg5.shortName == 'b');
	assert(arg5.helpMessage == "helpMe");
	assert(arg5.optional == Optional.no);
}

enum ArgsMatch {
	none,
	mustBeStruct,
	complete
}

ArgsMatch argsMatches(alias Args, string name, string Long, string Short)(
		string prefix, string opt) 
{
	import stringbuffer;
	import std.format : formattedWrite;
	import std.algorithm.searching : startsWith, canFind;

	StringBuffer buf;
	formattedWrite!"%s%s%s"(buf.writer(), Long, prefix, name);

	//writeln("argsMatches ", buf.getData(), "' '", prefix, "' '", opt, "'");
	if(opt.startsWith(buf.getData())) {
		return opt == buf.getData() ? ArgsMatch.complete :
			ArgsMatch.mustBeStruct;
	} else if(Args.shortName == '\0') {
		return ArgsMatch.none;
	}

	buf.removeAll();
	formattedWrite!"%s%s"(buf.writer(), Short, Args.shortName);

	if(buf.getData() == opt) {
		return ArgsMatch.complete;
	}

	return ArgsMatch.none;
}

bool parseArgsImpl(string mem, string Long, string Short, Opt, Args)(
		ref Opt opt, string prefix, ref Args args) 
{
	import std.traits : hasUDA, getUDAs, isArray, isSomeString;
	import std.algorithm.searching : canFind;
	import std.algorithm.iteration : splitter, map;
	import std.range : ElementEncodingType;
	import std.array : array;
	import std.conv : to;

	static if(hasUDA!(__traits(getMember, opt, mem), Argument)) {
		Argument optMemArg = getUDAs!(__traits(getMember, opt, mem), Argument)[0];
		size_t idx = 1;
		while(args.length > 1) {
			auto arg = args[idx];
			if(arg == "--help" || arg == "-h") {
				args = remove(args, idx);
				return true;
			}
			ArgsMatch matchType = argsMatches!(optMemArg, mem, Long, Short)
				(prefix, arg);
			if(matchType == ArgsMatch.mustBeStruct) {
				static if(is(typeof(__traits(getMember, opt, mem)) == struct)) {
					parseArgs!(Long, Short)(__traits(getMember, opt, mem), 
							prefix ~ mem ~ ".", args
						);
					return false;
				} else {
					throw new Exception("Argument '" ~ arg ~ "' was prefix but"
							~ " '" ~ mem ~ "' was not an embedded struct.");
				}
			} else if(matchType == ArgsMatch.complete) {
				static if(is(typeof(__traits(getMember, opt, mem)) == bool)) 
				{
					__traits(getMember, opt, mem) = true;
					args = remove(args, idx);
				} else static if(
						!is(typeof(__traits(getMember, opt, mem)) == struct)
						&& isArray!((typeof(__traits(getMember, opt, mem))))
				) {
					if(idx + 1 >= args.length) {
						throw new Exception("Not enough arguments passed for '"
								~ arg ~ "' arg.");
					}
					static if(isSomeString!(typeof(__traits(getMember, opt, mem))))
					{
						__traits(getMember, opt, mem) =
							to!(typeof(__traits(getMember, opt, mem)))(
								args[idx + 1]
							);
					} else {
						alias ToType = typeof(__traits(getMember, opt, mem)[0]);
						if(args[idx + 1].canFind(',')) {
							__traits(getMember, opt, mem) ~= 
								args[idx + 1].splitter(',')
								.map!(a => to!(ToType)(a))
								.array;
						} else {
							__traits(getMember, opt, mem) ~= 
								to!(ToType)(
									args[idx + 1]
								);
						}
					}
					args = remove(args, idx);
					args = remove(args, idx);
					continue;
				} else static if(
						!is(typeof(__traits(getMember, opt, mem)) == struct)
						&& !isArray!((typeof(__traits(getMember, opt, mem))))
				) {
					if(idx + 1 >= args.length) {
						throw new Exception("Not enough arguments passed for '"
								~ arg ~ "' arg.");
					}
					__traits(getMember, opt, mem) = 
						to!(typeof(__traits(getMember, opt, mem)))(args[idx + 1]);
					args = remove(args, idx);
					args = remove(args, idx);
					return false;
				}
			} else if(matchType == ArgsMatch.none) {
				return false;
			}
		}
		if(optMemArg.optional == Optional.no) {
			throw new Exception("Non Optional argument for '" ~ mem 
					~ "' not found.");
		}
	}
	return false;
}

private ref T remove(T)(return ref T arr, size_t idx) {
	import std.traits : isArray;

	static if(isArray!T) {
		import std.algorithm.mutation : remove;
		arr = remove(arr, idx);
		return arr;
	} else {
		auto r = arr[idx .. idx + 1];
		arr.linearRemove(r);
		return arr;
	}
}

unittest {
	import std.algorithm.comparison : equal;

	Array!int a;
	a.insertBack([0,1,2,3]);
	a = remove(a, 1);
	assert(equal(a[], [0,2,3]));
}

struct UniqueShort {
	int[128] used;
}

UniqueShort checkUniqueRecur(Opt)() {
	import std.traits : hasUDA, getUDAs;
	UniqueShort ret;
	foreach(mem; __traits(allMembers, Opt)) {
		static if(hasUDA!(__traits(getMember, Opt, mem), Argument)) {
			static if(is(typeof(__traits(getMember, Opt, mem)) == struct)) {
				enum recur = checkUniqueRecur!(
						typeof(__traits(getMember, Opt, mem))
					);
				foreach(idx, it; recur.used) {
					ret.used[idx] += it;
				}
			} else {
				Argument optMemArg = getUDAs!(
						__traits(getMember, Opt, mem), Argument
					)[0];
				if(optMemArg.shortName != '\0') {
					ret.used[cast(size_t)optMemArg.shortName]++;
				}
			}
		}
	}
	return ret;
}

void checkUnique(Opt)() {
	import std.array : appender;
	import std.format : formattedWrite;
	enum unique = checkUniqueRecur!(Opt)();
	bool ok = true;
	string errMsg;
	auto app = appender!string();
	foreach(idx, it; unique.used) {
		if(it > 1) {
			formattedWrite(app, 
					"The short option name '%s' was used %d times.\n",
					cast(char)idx, it
				);
			ok = false;
		}
	}

	if(unique.used[cast(size_t)'h'] == 1) {
		formattedWrite(app, 
				"The short option name 'h' are not allowed as they are "
				~ "reservered the help dialog.\n");
		ok = false;
	}

	if(!ok) {
		throw new Exception(app.data);
	}
}

unittest {
	static struct F {
		@Arg() int foo;
	}

	F f;
	auto args = ["funcname", "--foo", "10"];
	parseArgsImpl!("foo", "--", "-")(f, "", args);
	assert(f.foo == 10);
	assert(args.length == 1);
	assert(args[0] == "funcname");
}

private bool parseArgs(string Long, string Short, Opt, Args)(ref Opt opt, 
		string prefix, ref Args args) 
{
	checkUnique!Opt();

	bool helpWanted = false;

	foreach(optMem; __traits(allMembers, Opt)) {
		helpWanted |= parseArgsImpl!(optMem, Long, Short)(opt, prefix, args);
	}
	return helpWanted;
}

size_t longOptionsWidth(Opt)(string prefix = "") {
	import std.traits : hasUDA;
	import std.algorithm.comparison : max;
	size_t ret;
	foreach(mem; __traits(allMembers, Opt)) {
		static if(hasUDA!(__traits(getMember, Opt, mem), Argument)) {
			static if(is(typeof(__traits(getMember, Opt, mem)) == struct)) {
				enum s = longOptionsWidth!(typeof(__traits(getMember, Opt, mem)))(mem ~ ".");
				ret = max(ret, s);
			} else {
				ret = max(ret, mem.length);
			}
		}
	}
	return ret;
}

size_t typeWidth(Opt)() {
	import std.traits : hasUDA, Unqual;
	import std.algorithm.comparison : max;
	size_t ret;
	foreach(mem; __traits(allMembers, Opt)) {
		static if(hasUDA!(__traits(getMember, Opt, mem), Argument)) {
			static if(is(typeof(__traits(getMember, Opt, mem)) == struct)) {
				enum s = typeWidth!(typeof(__traits(getMember, Opt, mem)))();
				ret = max(ret, s);
			} else {
				enum memLen = Unqual!(typeof(__traits(getMember, Opt, mem))).stringof.length;
				ret = max(ret, memLen);
			}
		}
	}
	return ret;
}

size_t defaultWidth(Opt)(const ref Opt opt) @safe {
	import std.traits : hasUDA, Unqual;
	import std.algorithm.comparison : max;
	import stringbuffer;
	import std.format : formattedWrite;
	StringBuffer buf;
	size_t ret;
	foreach(mem; __traits(allMembers, Opt)) {
		static if(hasUDA!(__traits(getMember, Opt, mem), Argument)) {
			static if(is(typeof(__traits(getMember, Opt, mem)) == struct)) {
				auto s = defaultWidth!(typeof(__traits(getMember, Opt, mem)))
					(__traits(getMember, opt, mem));
				ret = max(ret, s);
			} else {
				buf.removeAll();
				formattedWrite(buf.writer(), "%s", __traits(getMember, opt,
							mem));
				ret = max(ret, buf.length);
			}
		}
	}
	return ret;
}

void printArgsHelp(Opt)(ref const(Opt) opt, string header) {
	import std.stdio : stdout;
	auto ltw = stdout.lockingTextWriter();
	printArgsHelp(ltw, opt, header);
}

void printArgsHelp(LTW, Opt)(ref LTW ltw, ref const(Opt) opt, string header) {
	import std.format : formattedWrite;		
	formattedWrite(ltw, "%s\n", header);

	enum lLength = longOptionsWidth!(Opt)("");
	enum tLength = typeWidth!(Opt)();
	auto dLength = defaultWidth!(Opt)(opt) + 2;
	printArgsHelpImpl!(lLength + 4, tLength + 2)(opt, ltw, dLength, "");
}

private void printArgsHelpImpl(size_t longLength, size_t typeLength, Opt, LTW)(
		ref const(Opt) opt, ref LTW ltw, const size_t dLength, string prefix) 
{
	import std.traits : hasUDA, getUDAs, Unqual;
	import std.format : formattedWrite;		
	foreach(mem; __traits(allMembers, Opt)) {
		static if(hasUDA!(__traits(getMember, opt, mem), Argument)) {
			Argument optMemArg = getUDAs!(__traits(getMember, opt, mem), Argument)[0];
			static if(is(typeof(__traits(getMember, Opt, mem)) == struct)) {
				printArgsHelpImpl!(longLength, typeLength)(__traits(getMember, opt, mem), 
						ltw, dLength, mem ~ ".");
			} else {
				if(optMemArg.shortName != '\0') {
					formattedWrite(ltw, "-%s   ", optMemArg.shortName);
				} else {
					formattedWrite(ltw, "     ");
				}
				formattedWrite(ltw, "%-*s Type: %-*s default: %-*s",
						longLength, "--" ~ prefix ~ mem, 
						typeLength, 
						Unqual!(typeof(__traits(getMember, opt, mem))).stringof,
						dLength, __traits(getMember, opt, mem)
					);
				printHelpMessage(ltw, optMemArg, 
						longLength + typeLength + dLength
					);
			}
		}
	}
}

private void printHelpMessage(LTW)(ref LTW ltw, ref const(Argument) optMemArg,
		const size_t beforeLength) 
{
	import std.format : formattedWrite;		
	formattedWrite(ltw, "%5s", "Help: ");
	int curLength;
	enum staticOffset = 28;
	immutable helpStartLength = (beforeLength + staticOffset);
	immutable helpBreakLength = 100 - helpStartLength;
	foreach(dchar it; optMemArg.helpMessage) {
		if(it == '\n' || it == '\t') {
			formattedWrite(ltw, "%s", ' ');
			++curLength;
			continue;
		}
		if(it == ' ' && curLength > helpBreakLength) {
			formattedWrite(ltw, "\n");
			formattedWrite(ltw, "%*s", helpStartLength, " ");
			curLength = 0;
			continue;
		}
		formattedWrite(ltw, "%s", it);
		++curLength;
	}
	formattedWrite(ltw, "\n");
}

unittest {
	static struct Options {
		@Arg() int a = 1;
		@Arg("", 'c') int b = 2;
		@Arg() bool d;
	}

	auto args = ["funcname", "--a", "10", "-c", "11", "--d"];
	Options opt;
	parseArgs(opt, args);
	assert(opt.a == 10);
	assert(opt.b == 11);
	assert(opt.d == true);
}

unittest {
	static struct Options {
		@Arg() int a = 1;
		@Arg("", 'c') int b = 2;
		@Arg() bool d;
	}

	Options opt;
	auto args = [["funcname", "-h"], ["funcname", "--help"]];
	foreach(arg; args) {
		assert(parseArgs(opt, arg));
	}
}

unittest {
	import std.exception : assertThrown;
	import std.conv : to;

	static struct Options {
		@Arg(Optional.no) int a = 1;
	}

	auto args = ["funcname", "--a", "11", "--d"];
	Options opt;
	parseArgs(opt, args);
	assert(args.length == 2, to!string(args.length));
	assert(args[0] == "funcname");
	assert(args[1] == "--d");
}

unittest {
	import std.exception : assertThrown;
	import std.conv : to;

	static struct Options {
		@Arg(Optional.no) int a = 1;
	}

	auto args = ["funcname"];
	Options opt;
	assertThrown!Exception(parseArgs(opt, args));
	assert(args.length == 1, to!string(args.length));
}

unittest {
	import std.exception : assertThrown;

	static struct Options {
		@Arg() int a = 1;
	}

	auto args = ["funcname", "--a"];
	Options opt;
	assertThrown!(Exception)(parseArgs(opt, args));
}

unittest {
	import std.exception : assertThrown;

	static struct Embed {
		@Arg() int b = 2;
	}

	static struct Options {
		@Arg() int a = 1;
		@Arg() Embed embed;
	}

	auto args = ["funcname", "--a", "10", "--embed.b", "20"];
	Options opt;
	parseArgs(opt, args);
	assert(opt.a == 10);
	assert(opt.embed.b == 20);
}

unittest {
	import std.exception : assertThrown;

	static struct Options {
		@Arg() int a = 1;
		@Arg() int embed;
	}

	auto args = ["funcname", "--a", "10", "--embed.b", "20"];
	Options opt;
	assertThrown!Exception(parseArgs(opt, args));
}

unittest {
	import std.exception : assertThrown;
	import std.format : format;
	import std.conv : to;

	enum Enum {
		yes,
		no
	}

	static struct Embed2 {
		@Arg('z', "A super long and not helpful help message that should be"
			~ " very long") 
		Enum engage = Enum.yes;
	}

	static struct Embed {
		@Arg() Embed2 en2;
	}

	static struct Options {
		@Arg() int someValue = 1;
		@Arg() Embed en;
	}

	Options opt;
	auto data = parseArgsConfigFile("testfile.argsd");
	writefln("%(%s %)", data[]);
	parseConfigFile(opt, data);

	assert(opt.someValue == 100, format("%d %(%s %)",
			opt.someValue, data[]));
	assert(opt.en.en2.engage == Enum.no, format("%s %(%s %)",
			opt.en.en2.engage, data[]));
}

unittest {
	import std.exception : assertThrown;
	import stringbuffer;
	import std.format : format;

	enum Enum {
		yes,
		no
	}

	static struct Embed2 {
		@Arg('z', "A super long and not helpful help message that should be"
			~ " very long") 
		Enum engage = Enum.yes;
	}

	static struct Embed {
		@Arg() Embed2 en2;
	}

	static struct Options {
		@Arg() int someValueABCDEF = 1;
		@Arg() Embed en;
	}

	auto args = ["funcname", "--someValueABCDEF", "10", "--en.en2.e", "yes"];
	Options opt;
	parseArgs(opt, args);
	assert(opt.someValueABCDEF == 10);
	assert(opt.en.en2.engage == Enum.yes);

	StringBuffer buf;
	auto w = buf.writer();
	printArgsHelp(w, opt, "Some info");

	string expected =
`Some info
     --someValueABCDEF   Type: int    default: 10   Help: 
-z   --en2.engage        Type: Enum   default: yes  Help: A super long and not helpful help message that
                                                          should be very long
`;
	assert(buf.getData() == expected,
		format("\n'%s'\n '%s'", buf.getData(), expected)
	);
}

unittest {
	import std.exception : assertThrown;
	static struct Option {
		@Arg('a') int a;
		@Arg('a') int b;
	}

	auto args = ["funcname", "-a", "10"];
	Option opt;
	assertThrown!Exception(parseArgs(opt, args));
}

unittest {
	import std.algorithm.comparison : equal;
	import std.format : format;

	static struct Option {
		@Arg() int[] a;
	}

	auto args = ["funcname", "--a", "10", "--a", "20"];
	Option opt;
	parseArgs(opt, args);
	assert(equal(opt.a, [10,20]), format("\"%(%s %)\"", opt.a));
}

unittest {
	import std.algorithm.comparison : equal;
	import std.format : format;

	static struct Option {
		@Arg() int[] a;
	}

	auto args = ["funcname", "--a", "10,20"];
	Option opt;
	parseArgs(opt, args);
	assert(equal(opt.a, [10,20]), format("\"%(%s %)\"", opt.a));
}

unittest {
	import std.exception : assertThrown;

	enum Enum {
		yes,
		no
	}

	static struct Embed2 {
		@Arg('b') 
		Enum e = Enum.yes;
	}

	static struct Embed {
		@Arg() Embed2 en2;
	}

	static struct Options {
		@Arg('b') int a = 1;
		@Arg() Embed en;
	}

	auto args = ["funcname", "--a", "10", "--en.en2.e", "yes"];
	Options opt;
	assertThrown!Exception(parseArgs(opt, args));
}
