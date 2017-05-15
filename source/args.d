import args;

import std.array : front;
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

bool parseImpl(string mem, Opt)(ref Opt opt, ref string[] args) {
	import std.traits : hasUDA, getUDAs;
	import std.algorithm.searching : startsWith, canFind;
	import std.algorithm.mutation : remove;
	import std.string : indexOf;
	import std.conv : to;

	static if(hasUDA!(__traits(getMember, opt, mem), Argument)) {
		Argument optMemArg = getUDAs!(__traits(getMember, opt, mem), Argument)[0];
		foreach(idx, arg; args) {
			if((arg.startsWith("--") && arg.canFind(mem) )
					|| (optMemArg.shortName != '\0' 
						&& arg.startsWith("-") 
						&& arg.canFind(optMemArg.shortName)) )
			{
				static if(is(typeof(__traits(getMember, opt, mem)) == bool)) {
					__traits(getMember, opt, mem) = true;
				} else {
					if(idx + 1 > args.length) {
						throw new Exception("Not enough arguments passed for '"
								~ arg ~ "' arg.");
					}
					__traits(getMember, opt, mem) = 
						to!(typeof(__traits(getMember, opt, mem)))(args[idx + 1]);
					args = remove(args, idx);
				}
				args = remove(args, idx);
				return true;
			}
		}
	}
	return false;
}

void parseCommandLineArguments(Opt)(ref Opt opt, string prefix, ref string[] args) 
{
	foreach(optMem; __traits(allMembers, Opt)) {
		if(!parseImpl!(optMem)(opt, args)) {
			throw new Exception("No Option for '" ~ args.front ~ "' found");
		}
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
	parseCommandLineArguments(opt, "", args);
	assert(opt.a == 10);
	assert(opt.b == 11);
	assert(opt.d == true);
}
