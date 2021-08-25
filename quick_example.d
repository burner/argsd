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
