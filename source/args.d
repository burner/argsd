import args;

import std.array : empty, front;
import std.stdio;

enum Optional {
	yes,
	no
}

struct Multiplicity {
	size_t min;
	size_t max;
}

struct Argument {
	bool isArgument = false;
	string helpMessage;
	char shortName = '\0';
	Multiplicity multiplicity;
	Optional optional = Optional.yes;

	this(T...)(T args) {
		this.shortName = '\0';
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
		} else static if(is(T[0] == Multiplicity)) {
			this.multiplicity = args[0];
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
			 	getUDAs!(T, Argument)[0].multiplicity,
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
	assert(arg.multiplicity.min == 0);
	assert(arg.multiplicity.max == 0);
	assert(arg.optional == Optional.yes);

	@Arg("", 'b') int b;
	Argument arg2 = getArgs!(b);
	assert(arg2.shortName == 'b');
	assert(arg2.helpMessage == "");
	assert(arg2.multiplicity.min == 0);
	assert(arg2.multiplicity.max == 0);
	assert(arg2.optional == Optional.yes);

	@Arg("helpMe", 'b') int c;
	Argument arg3 = getArgs!(c);
	assert(arg3.shortName == 'b');
	assert(arg3.helpMessage == "helpMe");
	assert(arg3.multiplicity.min == 0);
	assert(arg3.multiplicity.max == 0);
	assert(arg3.optional == Optional.yes);

	@Arg("helpMe", 'b', Multiplicity(10,20)) int d;
	Argument arg4 = getArgs!(d);
	assert(arg4.shortName == 'b');
	assert(arg4.helpMessage == "helpMe");
	assert(arg4.multiplicity.min == 10);
	assert(arg4.multiplicity.max == 20);
	assert(arg4.optional == Optional.yes);

	@Arg("helpMe", 'b', Optional.no, Multiplicity(10,20)) int e;
	Argument arg5 = getArgs!(e);
	assert(arg5.shortName == 'b');
	assert(arg5.helpMessage == "helpMe");
	assert(arg5.multiplicity.min == 10);
	assert(arg5.multiplicity.max == 20);
	assert(arg5.optional == Optional.no);
}

enum ArgsMatch {
	none,
	mustBeStruct,
	complete
}

ArgsMatch argsMatches(alias Args, string name)(string prefix, string opt) {
	import stringbuffer;
	import std.format : formattedWrite;
	import std.algorithm.searching : startsWith, canFind;

	StringBuffer buf;
	formattedWrite!"--%s%s"(buf.writer(), prefix, name);

	//writeln(buf.getData(), "' '", prefix, "' '", name, "' '", opt, "'");
	if(opt.startsWith(buf.getData())) {
		return opt == buf.getData() ? ArgsMatch.complete :
			ArgsMatch.mustBeStruct;
	} else if(Args.shortName == '\0') {
		return ArgsMatch.none;
	}

	buf.removeAll();
	formattedWrite!"-%s"(buf.writer(), Args.shortName);

	if(buf.getData() == opt) {
		return ArgsMatch.complete;
	}

	return ArgsMatch.none;
}

void parseArgsImpl(string mem, Opt)(ref Opt opt, string prefix, 
		ref string[] args) 
{
	import std.traits : hasUDA, getUDAs;
	import std.algorithm.mutation : remove;
	import std.conv : to;

	static if(hasUDA!(__traits(getMember, opt, mem), Argument)) {
		Argument optMemArg = getUDAs!(__traits(getMember, opt, mem), Argument)[0];
		foreach(idx, arg; args) {
			ArgsMatch matchType = argsMatches!(optMemArg, mem)(prefix, arg);
			if(matchType == ArgsMatch.mustBeStruct) {
				static if(is(typeof(__traits(getMember, opt, mem)) == struct)) {
					parseArgs(__traits(getMember, opt, mem), mem ~ ".", args);
					return;
				} else {
					throw new Exception("Argument '" ~ arg ~ "' was prefix but"
							~ " '" ~ mem ~ "' was not an embedded struct.");
				}
			} else if(matchType.complete) {
				static if(is(typeof(__traits(getMember, opt, mem)) == bool)) 
				{
					__traits(getMember, opt, mem) = true;
					args = remove(args, idx);
				} else static if(!is(typeof(__traits(getMember, opt, mem)) == struct)) {
					if(idx + 1 >= args.length) {
						throw new Exception("Not enough arguments passed for '"
								~ arg ~ "' arg.");
					}
					__traits(getMember, opt, mem) = 
						to!(typeof(__traits(getMember, opt, mem)))(args[idx + 1]);
					args = remove(args, idx);
					args = remove(args, idx);
				}
				return;
			}
		}
		if(optMemArg.optional == Optional.no) {
			throw new Exception("Non Optional argument for '" ~ mem 
					~ "' not found.");
		}
	}
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
					"The short option '%s' was used multiple times.\n",
					cast(char)idx
				);
			ok = false;
		}
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
	auto args = ["--foo", "10"];
	parseArgsImpl!("foo")(f, "", args);
	assert(f.foo == 10);
	assert(args.length == 0);
}

void parseArgs(Opt)(ref Opt opt, ref string[] args) 
{
	parseArgs(opt, "", args);
}

void parseArgs(Opt)(ref Opt opt, string prefix, ref string[] args) 
{
	checkUnique!Opt();
	foreach(optMem; __traits(allMembers, Opt)) {
		parseArgsImpl!(optMem)(opt, prefix, args);
	}
}

unittest {
	static struct Options {
		@Arg() int a = 1;
		@Arg("", 'c') int b = 2;
		@Arg() bool d;
	}

	auto args = ["--a", "10", "-c", "11", "--d"];
	Options opt;
	parseArgs(opt, args);
	assert(opt.a == 10);
	assert(opt.b == 11);
	assert(opt.d == true);
}

unittest {
	import std.exception : assertThrown;

	static struct Options {
		@Arg(Optional.no) int a = 1;
	}

	auto args = ["-c", "11", "--d"];
	Options opt;
	parseArgs(opt, args);
	assert(args.length == 1);
	assert(args[0] == "--d");
}

unittest {
	import std.exception : assertThrown;

	static struct Options {
		@Arg() int a = 1;
	}

	auto args = ["--a"];
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

	auto args = ["--a", "10", "--embed.b", "20"];
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

	auto args = ["--a", "10", "--embed.b", "20"];
	Options opt;
	assertThrown!Exception(parseArgs(opt, args));
}

unittest {
	import std.exception : assertThrown;

	enum Enum {
		yes,
		no
	}

	static struct Embed2 {
		@Arg() Enum e = Enum.yes;
	}

	static struct Embed {
		@Arg() Embed2 en2;
	}

	static struct Options {
		@Arg() int a = 1;
		@Arg() Embed en;
	}

	auto args = ["--a", "10", "--en.en2.e", "yes"];
	Options opt;
	parseArgs(opt, args);
	assert(opt.a == 10);
	assert(opt.en.en2.e == Enum.yes);
}

unittest {
	import std.exception : assertThrown;
	static struct Option {
		@Arg('a') int a;
		@Arg('a') int b;
	}

	auto args = ["-a", "10"];
	Option opt;
	assertThrown!Exception(parseArgs(opt, args));
}

unittest {
	import std.exception : assertThrown;

	enum Enum {
		yes,
		no
	}

	static struct Embed2 {
		@Arg('b') Enum e = Enum.yes;
	}

	static struct Embed {
		@Arg() Embed2 en2;
	}

	static struct Options {
		@Arg('b') int a = 1;
		@Arg() Embed en;
	}

	auto args = ["--a", "10", "--en.en2.e", "yes"];
	Options opt;
	assertThrown!Exception(parseArgs(opt, args));
}
