// Application fixture: --json and --help belong to its opaque argv. Its JSON
// document is the whole stdout result; the parent must append no second one.
process.stdout.write(JSON.stringify({ok: true, argv: process.argv.slice(2)}) + '\n');
process.exitCode = 23;
