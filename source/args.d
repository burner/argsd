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
	string name;
	string helpMessage;
	Multiplicity multiplicity;
	Optional optional;

	this(T...)(T args) {
		this.optional = Optional.yes;

		static if(T.length > 0) {
			construct(0, args);
		}
	}

	void construct(T...)(size_t stringPos, T args) {
		import std.traits : isSomeString;
		static if(isSomeString!(T[0])) {
			if(stringPos == 0) {
				this.name = args[0];
			} else if(stringPos == 1) {
				this.helpMessage = args[0];
			}
			++stringPos;
		} else static if(is(T[0] == Multiplicity)) {
			this.multiplicity = args[0];
		} else static if(is(T[0] == Optional)) {
			this.optional = args[0];
		}

		static if(T.length > 1) {
			construct(stringPos, args[1 .. $]);
		}
	}
}

Argument Arg(T...)(T args) {
	return Argument(args);
}

Argument getArgs(alias T)() {
	import std.traits : hasUDA, getUDAs;
	static if(hasUDA!(T, Argument)) {
		return Argument(getUDAs!(T, Argument)[0].name, 
				getUDAs!(T, Argument)[0].helpMessage,
			 	getUDAs!(T, Argument)[0].multiplicity,
				getUDAs!(T, Argument)[0].optional);
	} else {
		return Argument();
	}
}

unittest {
	@Arg() int a;
	Argument arg = getArgs!(a);
	assert(arg.name == "");
	assert(arg.helpMessage == "");
	assert(arg.multiplicity.min == 0);
	assert(arg.multiplicity.max == 0);
	assert(arg.optional == Optional.yes);

	@Arg("notB") int b;
	Argument arg2 = getArgs!(b);
	assert(arg2.name == "notB");
	assert(arg2.helpMessage == "");
	assert(arg2.multiplicity.min == 0);
	assert(arg2.multiplicity.max == 0);
	assert(arg2.optional == Optional.yes);

	@Arg("notB", "helpMe") int c;
	Argument arg3 = getArgs!(c);
	assert(arg3.name == "notB");
	assert(arg3.helpMessage == "helpMe");
	assert(arg3.multiplicity.min == 0);
	assert(arg3.multiplicity.max == 0);
	assert(arg3.optional == Optional.yes);

	@Arg("notB", "helpMe", Multiplicity(10,20)) int d;
	Argument arg4 = getArgs!(d);
	assert(arg4.name == "notB");
	assert(arg4.helpMessage == "helpMe");
	assert(arg4.multiplicity.min == 10);
	assert(arg4.multiplicity.max == 20);
	assert(arg4.optional == Optional.yes);

	@Arg("notB", "helpMe", Optional.no, Multiplicity(10,20)) int e;
	Argument arg5 = getArgs!(e);
	assert(arg5.name == "notB");
	assert(arg5.helpMessage == "helpMe");
	assert(arg5.multiplicity.min == 10);
	assert(arg5.multiplicity.max == 20);
	assert(arg5.optional == Optional.no);
}
