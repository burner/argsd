import args;

import std.container.array : Array;
import std.array : empty, front;

@safe:

@safe unittest {
	/** argsd arguments are structures as shown below.
	Each argument that should be searched for needs to have $(D @Arg())
	attached to it.
	$(D @Arg()) takes three kinds of parameter.
	1. A $(D string) which is used as the help message for that argument.
	2. A $(D char) which is used as the character for the short argument
	selector.
	3. A $(D Optional) value to make the argument as optional or not (default
	Optional.yes).
	The order of the three parameter is not relevant.
	Arguments can be nested, see the nested $(D NestedArgument) $(D struct) in
	$(D MyAppArguments).
	Arguments can be of all primitive types, arrays of primitive types and $(D
	enum)s.

	All arguments take the shape "name value". Equal sign syntax is not
	supported.
	Array values can be given as separate values of as comma separated values.

	The name of the argument will be derived from the name of the member in
	the struct. The names are case sensitive.
	Arguments in nested structs have the name of the struct prefixed (compare
	"--nested.someFloatValue).

	Short names must be unique. If they are not unique an Exception will be
	thrown. Short names are used by prefixing the character with a single "-".
	The short name "-h" is reserved for requestion the help page.

	Long names are unique by definition. Long names are prefixed with "--".
	The long name "--help" is reserved for requestion the help page.

	If $(D parseArgsWithConfigFile) is used two more long names are reserved,
	"--config", and "--genConfig". Both take a $(D string) as argument.
	"--config filename" will try to parse the file with name $(I filename) and
	assign the values in that file to the argument struct passed.

	"--genConfig filename" can be used to create a config file with
	the default values of the argument struct. The name of the config file is
	again $(I filename).
	*/


	/** A enum used inside of NestedArguments */
	enum NestedEnumArgument {
		one,
		two,
		many
	}

	/** A struct nested in MyAppArguments */
	static struct NestedArguments {
		@Arg("Important Help Message") float someFloatValue;

		// D allows to assign default values to the arguments
		@Arg('z') NestedEnumArgument enumArg = NestedEnumArgument.two;
		@Arg() bool someBool;
	}

	/** The options to the created program. */
	static struct MyAppArguments {
		@Arg(Optional.no) string inputFilename;
		@Arg('b') int[] testValues;

		/** All options inside of $(D nested) need to be prefixed with
		  "nested.".
		*/
		@Arg() NestedArguments nested;

		@Arg('c', "Some good doc", Optional.no) string c;
	}

	import std.algorithm.comparison : equal;
	import std.format : format;
	import std.math : approxEqual;
	import std.array : appender;

	/** It is good practice to have the arguments write-protected by default.
	The following three declarations show a possible implementation.
	In order to look up a argument the developer would use the $(D config())
	function, returning him a write-protected version of the arguments.
	In order to populate the arguments the writable version returned from
	$(D configWriteable) is passed to $(D parseArgsWithConfigFile).
	This, and the option definitions is usually placed in a separate file and
	the visibility of $(D MyAppArguments arguments) is set to $(D private).
	*/
	MyAppArguments arguments;

	ref MyAppArguments configWriteable() {
		return arguments;
	}

	ref const(MyAppArguments) config() {
		return arguments;
	}

	/** This $(D string[]) serves as an example of what would be passed to the
	$(D main) function from the command line.
	*/
	string[] args = ["./executablename",
		"--nested.someBool",
		"--nested.someFloatValue", "12.34",
		"--testValues", "10",
		"-b", "11,12",
		"--nested.enumArg", "many",
		"--inputFilename", "nice.d",
		"-c", "aaa"];

	/** Populates the argument struct returned from configWriteable with the
	values passed in $(D args).

	$(D true) is returned if the help page is requested with either "-h" or
	"--help".
	$(D parseArgsWithConfigFile), and $(D parseArgs) will remove all used
	strings from $(D args).
	After the unused strings and the application name are left in $(D args).

	Replacing $(D parseArgsWithConfigFile) with $(D parseArgs) will disable
	the config file parsing option.
	*/
	bool helpWanted = parseArgsWithConfigFile(configWriteable(), args);

	if(helpWanted) {
		/** If the help page is wanted by the user the $(D printArgsHelp)
		function can be used to print help page.
		*/
		printArgsHelp(config(), "A text explaining the program");
	}

	auto app = appender!string();
	printArgsHelp(app, config(), "A text explaining the program");

	/** Here it is tested if the parsing of $(D args) was successful. */
	assert(equal(config().testValues, [10,11,12]));
	assert(config().nested.enumArg == NestedEnumArgument.many);
	assert(approxEqual(config().nested.someFloatValue, 12.34));
	assert(config().nested.someBool);
	assert(config().inputFilename == "nice.d");
}

bool parseArgs(Opt,Args)(ref Opt opt, ref Args args) {
	return parseArgs!("--", "-")(opt, "", args);
}

struct ConfigFile {
	@Arg() string config;
	@Arg() string genConfig;
}

bool parseArgsWithConfigFile(Opt,Args)(ref Opt opt, ref Args args) @trusted {
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
	import std.file : exists, remove;

	static struct Embed {
		@Arg() int b = 2;
	}

	static struct Options {
		@Arg() int a = 1;
		@Arg() Embed embed;
	}

	string cfilename = "configfile.argsd";

	{
		Options options;
		auto args = ["funcname", "--genConfig", cfilename];
		assert(!parseArgsWithConfigFile(options, args));
	}
	{
		Options options;
		options.a = 20;
		options.embed.b = 30;
		auto args = ["funcname", "--config", cfilename];
		assert(!parseArgsWithConfigFile(options, args));
		assert(options.a == 1, format("%s", options.a));
		assert(options.embed.b == 2);
	}

	assert(exists(cfilename));
	remove(cfilename);
	assert(!exists(cfilename));
}

void writeConfigToFile(Opt)(string filename, ref Opt opt) @safe {
	import std.stdio : File;
	auto f = File(filename, "w");
	auto ltw = f.lockingTextWriter();
	writeConfigToFileImpl(opt, ltw, "");
}

void writeConfigToFileImpl(Opt,LTW)(ref Opt opt, ref LTW ltw, string prefix) @safe {
	import std.traits : hasUDA, getUDAs;
	import std.format : formattedWrite;
	import std.array;
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
				string[] testArr;
				static if (is(typeof(testArr) == typeof(__traits(getMember, opt, mem)))) {
					string[] optArr = __traits(getMember, opt, mem);
					string def = optArr[0];
					// special case: string[]
					formattedWrite(ltw, "%s%s = \"%s\"\n",
							prefix, mem, def
					);
				} else {
					formattedWrite(ltw, "%s%s = \"%s\"\n",
						prefix, mem, __traits(getMember, opt, mem)
					);
				}
			}
		}
	}
}

void printHelpMessageConfig(Type,LTW)(ref LTW ltw, ref const(Argument) arg) @safe {
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

Array!string parseArgsConfigFile(string filename) @trusted {
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

	this(T...)(T args) @safe {
		static if(T.length > 0) {
			this.isArgument = true;
			construct(0, args);
		}
	}

	void construct(T...)(T args) @safe {
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

@safe unittest {
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
		string prefix, string opt) @safe
{
	import std.array : Appender, appender;
	import std.format : formattedWrite;
	import std.algorithm.searching : startsWith, canFind;
	//import std.stdio;

	Appender!string buf = appender!string();
	formattedWrite(buf, "%s%s%s", Long, prefix, name);

	//writeln("argsMatches ", buf.getData(), "' '", prefix, "' '", opt, "'");
	if(opt.startsWith(buf.data)) {
		return opt == buf.data ? ArgsMatch.complete :
			ArgsMatch.mustBeStruct;
	}

	if(Args.shortName == '\0') {
		return ArgsMatch.none;
	}

	buf = appender!string();
	formattedWrite(buf, "%s%s", Short, Args.shortName);
	//writeln("argsMatches short ", buf.getData(), "' '", prefix, "' '", opt, "'");

	if(buf.data == opt) {
		return ArgsMatch.complete;
	}

	return ArgsMatch.none;
}

private bool isShort(string str) @safe pure {
	return str.length == 2 && str[0] == '-' && str[1] != '-';
}

unittest {
	assert(isShort("-a"));
	assert(!isShort("-"));
	assert(!isShort("--"));
	assert(!isShort(""));
}

private bool isBool(string str) @safe pure {
	import std.algorithm.mutation : strip;

	str = str.strip(' ');
	str = str.strip('"');

	return str == "true" || str == "false";
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

	bool matched = false;

	static if(hasUDA!(__traits(getMember, opt, mem), Argument)) {
		Argument optMemArg = getUDAs!(__traits(getMember, opt, mem), Argument)[0];
		size_t idx = 1;
		while(args.length > 1 && idx < args.length) {
			auto arg = args[idx];
			if(arg == "--help" || arg == "-h") {
				() @trusted {
					args = remove(args, idx);
				}();
				return true;
			}
			ArgsMatch matchType = argsMatches!(optMemArg, mem, Long, Short)
				(prefix, arg);
			if(matchType == ArgsMatch.complete) {
				static if(is(typeof(__traits(getMember, opt, mem)) == bool))
				{
					if(idx + 1 < args.length && isBool(args[idx + 1])) {
						__traits(getMember, opt, mem) = to!bool(args[idx + 1]);
						() @trusted {
							args = remove(args, idx);
						}();
					} else {
						__traits(getMember, opt, mem) = true;
					}
					() @trusted {
						args = remove(args, idx);
					}();
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
					() @trusted {
						args = remove(args, idx);
						args = remove(args, idx);
					}();
					matched = true;
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
					() @trusted {
						args = remove(args, idx);
						args = remove(args, idx);
					}();
					matched = true;
					return false;
				}
			} else if(isShort(arg)) {
				static if(is(typeof(__traits(getMember, opt, mem)) == struct)) {
					parseArgs!(Long, Short)(__traits(getMember, opt, mem),
							prefix ~ mem ~ ".", args
						);
					return false;
				} else {
					++idx;
					continue;
				}
			} else if(matchType == ArgsMatch.mustBeStruct) {
				static if(is(typeof(__traits(getMember, opt, mem)) == struct)) {
					parseArgs!(Long, Short)(__traits(getMember, opt, mem),
							prefix ~ mem ~ ".", args
						);
					return false;
				} else {
					throw new Exception("Argument '" ~ arg ~ "' was prefix but"
							~ " '" ~ mem ~ "' was not an embedded struct.");
				}
			} else if(matchType == ArgsMatch.none) {
				++idx;
			}
		}
		if(!matched && optMemArg.optional == Optional.no) {
			throw new Exception("Non Optional argument for '" ~ mem
					~ "' not found.");
		}
	}
	return false;
}

private ref T remove(T)(return ref T arr, size_t idx) @trusted {
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

@trusted unittest {
	import std.algorithm.comparison : equal;

	Array!int a;
	a.insertBack([0,1,2,3]);
	a = remove(a, 1);
	assert(equal(a[], [0,2,3]));
}

struct UniqueShort {
	int[128] used;
}

UniqueShort checkUniqueRecur(Opt)() @safe {
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

void checkUnique(Opt)() @safe {
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

size_t longOptionsWidth(Opt)(string prefix = "") @safe {
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
	return ret + prefix.length;
}

size_t typeWidth(Opt)() @safe {
	import std.traits : hasUDA, Unqual;
	import std.algorithm.comparison : max;
	size_t ret;
	foreach(mem; __traits(allMembers, Opt)) {
		static if(hasUDA!(__traits(getMember, Opt, mem), Argument)) {
			static if(is(typeof(__traits(getMember, Opt, mem)) == struct)) {
				enum s = typeWidth!(typeof(__traits(getMember, Opt, mem)))();
				ret = max(ret, s);
			} else {
				enum memLen = ArgsUnqual!(typeof(__traits(getMember, Opt, mem)))
					.length;
				ret = max(ret, memLen);
			}
		}
	}
	return ret;
}

size_t defaultWidth(Opt)(const ref Opt opt) @safe {
	import std.array : appender;
	import std.traits : hasUDA, Unqual;
	import std.algorithm.comparison : max;
	import std.format : formattedWrite;

	auto buf = appender!string();
	size_t ret;
	foreach(mem; __traits(allMembers, Opt)) {
		static if(hasUDA!(__traits(getMember, Opt, mem), Argument)) {
			static if(is(typeof(__traits(getMember, Opt, mem)) == struct)) {
				auto s = defaultWidth!(typeof(__traits(getMember, Opt, mem)))
					(__traits(getMember, opt, mem));
				ret = max(ret, s);
			} else {
				buf = appender!string();
				formattedWrite(buf, "%s", __traits(getMember, opt, mem));
				ret = max(ret, buf.data.length);
			}
		}
	}
	return ret;
}

void printArgsHelp(Opt)(ref const(Opt) opt, string header, const(size_t)
		termWidth = getTerminalWidth()) @trusted
{
	import std.stdio : stdout;
	auto ltw = stdout.lockingTextWriter();
	printArgsHelp(ltw, opt, header, termWidth);
}

void printArgsHelp(LTW, Opt)(ref LTW ltw, ref const(Opt) opt, string header,
		const(size_t) termWidth = getTerminalWidth())
{
	import std.format : formattedWrite;
	formattedWrite(ltw, "%s\n", header);

	enum lLength = longOptionsWidth!(Opt)("");
	enum tLength = typeWidth!(Opt)();
	auto dLength = defaultWidth!(Opt)(opt) + 2;
	printArgsHelpImpl!(lLength + 4, tLength + 2)(opt, ltw, dLength, "",
			termWidth
		);
}

string ArgsUnqual(T)() {
	import std.traits : Unqual, isArray;
	import std.range.primitives : ElementType;
	static if(isArray!(T)) {
		return ArgsUnqual!(ElementType!(T))() ~ "[]";
	} else {
		return Unqual!(T).stringof;
	}
}

@safe unittest {
	import std.traits : Unqual, isArray;
	import std.range : ElementEncodingType;
	enum Foo {
		a,
		b
	}

	assert(ArgsUnqual!(Foo[]) == "Foo[]");
	static assert(isArray!(Foo[]));
	assert(is(ElementEncodingType!(Foo[]) == enum));
	static assert(isArray!(Foo[]) && is(ElementEncodingType!(Foo[]) == enum));
}

private void printArgsHelpImpl(size_t longLength, size_t typeLength, Opt, LTW)(
		ref const(Opt) opt, ref LTW ltw, const size_t dLength, string prefix,
		const(size_t) termWidth)
{
	import std.array : appender, Appender;
	import std.traits : hasUDA, getUDAs, Unqual, isArray, isSomeString;
	import std.format : formattedWrite;
	import std.range.primitives : ElementEncodingType;
	foreach(mem; __traits(allMembers, Opt)) {
		static if(hasUDA!(__traits(getMember, opt, mem), Argument)) {
			Argument optMemArg = getUDAs!(__traits(getMember, opt, mem), Argument)[0];
			static if(is(typeof(__traits(getMember, Opt, mem)) == struct)) {
				printArgsHelpImpl!(longLength, typeLength)(__traits(getMember, opt, mem),
						ltw, dLength, mem ~ ".", termWidth);
			} else {
				if(optMemArg.shortName != '\0') {
					formattedWrite(ltw, "-%s   ", optMemArg.shortName);
				} else {
					formattedWrite(ltw, "     ");
				}
				formattedWrite(ltw, "%-*s Type: %-*s ",
						longLength, "--" ~ prefix ~ mem,
						typeLength,
						//Unqual!(typeof(__traits(getMember, opt, mem))).stringof,
						ArgsUnqual!(typeof(__traits(getMember, opt, mem))),
					);
				alias ArgType = Unqual!(typeof(__traits(getMember, opt, mem)));
				static if(isArray!(ArgType) && !isSomeString!(ArgType)) {
					Appender!string arrBuf = appender!string();
					formattedWrite(arrBuf, "[%(%s, %)]",
							__traits(getMember, opt, mem)
						);
					formattedWrite(ltw, "default: %-*s",
							dLength, arrBuf.data
						);
				} else {
					formattedWrite(ltw, "default: %-*s",
							dLength, __traits(getMember, opt, mem)
						);
				}
				printHelpMessage(ltw, optMemArg,
						longLength + typeLength + dLength, termWidth
					);
				static if(is(ArgType == enum)) {
					printEnumValues!(LTW, ArgType)(
							ltw, longLength + typeLength + dLength
						);
				} else static if(isArray!(ArgType)
						&& is(ElementEncodingType!(ArgType) == enum)
					)
				{
					printEnumValues!(LTW,
							ElementEncodingType!(ArgType))(
							ltw, longLength + typeLength + dLength
						);
				}
			}
		}
	}
}

private size_t getTerminalWidth() @trusted {
	version(Posix) {
		import core.sys.posix.sys.ioctl;
		winsize w;
		ioctl(0, TIOCGWINSZ, &w);
		return w.ws_col;
	} else {
		return 100u;
	}
}

private void printEnumValues(LTW,Opt)(ref LTW ltw, const(size_t) beforeLength) {
	import std.format : formattedWrite;
	import std.traits : EnumMembers;
	enum staticOffset = 44;
	immutable helpStartLength = (beforeLength + staticOffset);
	formattedWrite(ltw, "%*s", helpStartLength, "Possible values:");
	foreach(it; EnumMembers!(Opt)) {
		formattedWrite(ltw, "\n%*s", helpStartLength, it);
	}
	formattedWrite(ltw, "\n");
}

private void printHelpMessage(LTW)(ref LTW ltw, ref const(Argument) optMemArg,
		const size_t beforeLength, const(size_t) termWidth)
{
	import std.format : formattedWrite;
	//import std.stdio;
	formattedWrite(ltw, "%5s", "Help: ");
	int curLength;
	enum staticOffset = 28;
	immutable helpStartLength = (beforeLength + staticOffset);
	//writeln(termWidth);
	immutable helpBreakLength = termWidth - helpStartLength;
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

@safe:

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
		@Arg() bool d;
		@Arg() int c;
	}

	foreach(idx, arg; [
			["funcname", "--d", "false", "--c", "10"],
			["funcname", "--d", "true", "--c", "10"],
			["funcname", "--d", "--c", "10"]
		])
	{
		Options opt;
		parseArgs(opt, arg);
		if(idx == 0) {
			assert(opt.d == false);
		} else {
			assert(opt.d == true);
		}
		assert(opt.c == 10);
	}
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

@trusted unittest {
	import std.exception : assertThrown;
	import std.format : format;
	import std.conv : to;

	enum Enum {
		yes,
		no
	}

	static struct Embed2 {
		@Arg('z', "A super long and not helpful help message that should be\n"
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
	//writefln("%(%s %)", data[]);
	parseConfigFile(opt, data);

	assert(opt.someValue == 100, format("%d %(%s %)",
			opt.someValue, data[]));
	assert(opt.en.en2.engage == Enum.no, format("%s %(%s %)",
			opt.en.en2.engage, data[]));
}

@trusted unittest {
	import std.exception : assertThrown;
	import std.array : appender;
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
		@Arg() Enum[] arr;
	}

	auto args = ["funcname", "--someValueABCDEF", "10", "--en.en2.e", "yes"];
	Options opt;
	parseArgs(opt, args);
	assert(opt.someValueABCDEF == 10);
	assert(opt.en.en2.engage == Enum.yes);

	auto buf = appender!string();
	printArgsHelp(buf, opt, "Some info", 100);

	string expected =
`Some info
     --someValueABCDEF   Type: int      default: 10   Help:
-z   --en2.engage        Type: Enum     default: yes  Help: A super long and not helpful help message
                                                            that should be very long
                                                            Possible values:
                                                                         yes
                                                                          no
     --arr               Type: Enum[]   default: []   Help:
                                                            Possible values:
                                                                         yes
                                                                          no
`;
	assert(buf.data == expected,
		format("\n'%s'\n'%s'", buf.data, expected)
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

@trusted unittest {
	static struct Options {
		@Arg('s') string[] strings = ["arg1"];
	}

	Options opt;

	ref Options configWriteable() {
		return opt;
	}

	ref const(Options) config() {
		return opt;
	}

	// test command line arguments
	auto args = ["progname", "-s", "arg2", "--strings", "arg3"];
	assert(!parseArgsWithConfigFile(opt, args));

	const string[] strArr = config().strings;
	assert(strArr[0] == "arg1");
	assert(strArr[1] == "arg2");
	assert(strArr[2] == "arg3");

	// test config file parsing
	import std.file : remove;

	Options opt2;
	writeConfigToFile("stringTest.conf", opt2);
	auto data = parseArgsConfigFile("stringTest.conf");
	parseConfigFile(opt2, data);
	remove("stringTest.conf");


	// there should be two equal elements (arg1):
	// 1. the one set as default in the declaration of struct Options
	// 2. the one which has been read from the config file written in 1.
	assert(opt2.strings.length == 2);
	assert(opt2.strings[0] == "arg1");
	assert(opt2.strings[1] == "arg1");
}

unittest {
	import std.stdio;
	//writeln(__LINE__);

	enum Enum {
		yes,
		no
	}

	static struct Embed2 {
		@Arg('c')
		Enum e = Enum.yes;

		@Arg('d')
		int hello = 10;
	}

	static struct Embed {
		@Arg() Embed2 en2;
	}

	static struct Options {
		@Arg('b') int a = 1;
		@Arg() Embed en;
	}

	auto args = ["funcname", "-c", "no", "-b", "2", "-d", "22"];
	Options opt;
	parseArgs(opt, args);
	assert(opt.a == 2);
	assert(opt.en.en2.e == Enum.no);
	assert(opt.en.en2.hello == 22);
}
