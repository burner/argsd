import args;

import std.typecons : Flag;
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
	string helpMessage;
	char shortName = '\0';
	Multiplicity multiplicity;
	Optional optional = Optional.yes;

	this(T...)(T args) {
		static if(T.length > 0) {
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
	@Arg int a;
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

void parseCommandLineArguments(Opt)(ref Opt opt, string prefix, ref string[] args) {
	import std.traits : hasUDA, getUDAs;
	import std.algorithm.searching : startsWith, canFind;
	import std.string : indexOf;
	import std.conv : to;
	import std.array : front;

	con: while(args.length) {
		writeln(args[0]);
		foreach(optMem; __traits(allMembers, Opt)) {
			writeln(optMem[0], " ", args.front.indexOf("--") == 0);
			static if(hasUDA!(optMem, Argument)) {
				auto optMemArg = getArgs!(optMem);
				if(args.front.indexOf("--") == 0 && args.front.canFind(optMem)) {
					__traits(getMember, opt, optMem) = 
						to!(typeof(__traits(getMember, opt, optMem)))(
							args[1]
						);
					args = args[2 .. $];
					continue con;
				} else if(arg.shortName != '\0' 
						&& args.front.indexOf("-") == 0 && args.front.canFind(arg.shortName))
				{
					__traits(getMember, opt, optMem) = 
						to!(typeof(__traits(getMember, opt, optMem)))(
							args[1]
						);
					args = args[2 .. $];
					continue con;
				}
			}
		}
		throw new Exception("No matching option for '" ~ args[0] ~ "' found");
	}
}

unittest {
	static struct Options {
		@Arg int a = 1;
		@Arg("", 'c') int b = 2;
	}

	auto args = ["--a", "10", "-c", "11"];
	Options opt;
	parseCommandLineArguments(opt, "", args);
	assert(opt.a == 10);
}
