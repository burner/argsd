# args
![alt text](https://travis-ci.org/burner/argsd.svg?branch=master)

A command line and config file parser for DLang


## Quick Example
```d
import args : Arg, Optional, parseArgsWithConfigFile, printArgsHelp;

static struct MyOptions {
	@Arg("the input file", Optional.yes) string inputFilename;
	@Arg("test values", 't') int[] testValues;
	@Arg("Enable feature") bool enableFeature;
}

MyOptions getOptions(ref string[] args) {
	MyOptions options;

	bool helpWanted = parseArgsWithConfigFile(options, args);

	if (helpWanted) {
		printArgsHelp(options, "A text explaining the program");
	}
	return options;
}

void main(string[] args) {
	const options = getOptions(args); // or args.dup to keep the original args

	// use options here....
}
```

This gives:
```ps1
❯ ./quick_example --help
A text explaining the program
     --inputFilename   Type: dchar[]   default:        Help: the input file
-t   --testValues      Type: int[]     default: []     Help: test values
     --enableFeature   Type: bool      default: false  Help: Enable feature

```

## Explanation

`argsd` arguments are structures as shown below.
Each argument that should be searched for needs to have `@Arg()`
attached to it.

`@Arg()` takes three kinds of parameter.
1. A `string` which is used as the help message for that argument.
2. A `char` which is used as the character for the short argument
selector.
3. A `Optional` value to make the argument as optional or not (default
Optional.yes).
The order of the three parameter is not relevant.

Arguments can be nested, see the nested `NestedArgument struct` in
`MyAppArguments`.

Arguments can be of all primitive types, arrays of primitive types and `D
enum`s.

All arguments take the shape "name value". Equal sign syntax is not
supported.

Array values can be given as a comma separated list.

The name of the argument will be derived from the name of the member in
the struct. The names are case sensitive.

Arguments in nested structs have the name of the struct prefixed (compare
`--nested.someFloatValue`).

Short names must be unique. If they are not unique an Exception will be
thrown. Short names are used by prefixing the character with a single `-`.
The short name `-h` is reserved for requestion the help page.

Long names are unique by definition. Long names are prefixed with `--`.
The long name "--help" is reserved for requestion the help page.

If `parseArgsWithConfigFile` is used two more long names are reserved,
`--config`, and `--genConfig`. Both take a `string` as argument.
`--config filename` will try to parse the file with name `filename` and
assign the values in that file to the argument struct passed.

`--genConfig filename` can be used to create a config file with
the default values of the argument struct. The name of the config file is
again `filename`.


```d
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

	/** All options inside of nested need to be prefixed with
	  "nested.".
	*/
	@Arg() NestedArguments nested;
}

import std.algorithm.comparison : equal;
import std.format : format;
import std.math : isClose;
```

It is good practice to have the arguments write-protected by default.
The following three declarations show a possible implementation.

In order to look up a argument the developer would use the `config()`
function, returning him a write-protected version of the arguments.
In order to populate the arguments the writable version returned from
`configWriteable` is passed to `parseArgsWithConfigFile`.
This, and the option definitions is usually placed in a separate file and
the visibility of `MyAppArguments argument` is set to `D private`.

MyAppArguments arguments;

```d
ref MyAppArguments configWriteable() {
	return arguments;
}

ref const(MyAppArguments) config() {
	return arguments;
}
```

This `string[]` serves as an example of what would be passed to the
`main` function from the command line.

```d
string[] args = ["./executablename",
	"--nested.someBool",
	"--nested.someFloatValue", "12.34",
	"--testValues", "10",
	"-b", "11,12",
	"--nested.enumArg", "many",
	"--inputFilename", "nice.d"];
```

Populates the argument struct returned from configWriteable with the
values passed in `args`.

`true` is returned if the help page is requested with either `-h` or
`--help`.
`parseArgsWithConfigFile`, and `parseArgs` will remove all used
strings from `args`.
After the unused strings and the application name are left in `args`.

Replacing `parseArgsWithConfigFile` with `parseArgs` will disable
the config file parsing option.

```d
bool helpWanted = parseArgsWithConfigFile(configWriteable(), args);

if(helpWanted) {
	/** If the help page is wanted by the user the printArgsHelp
	function can be used to print help page.
	*/
	printArgsHelp(config(), "A text explaining the program");
}

/** Here it is tested if the parsing of args was successful. */
assert(equal(config().testValues, [10,11,12]));
assert(config().nested.enumArg == NestedEnumArgument.many);
assert(isClose(config().nested.someFloatValue, 12.34));
assert(config().nested.someBool);
assert(config().inputFilename == "nice.d");
```
