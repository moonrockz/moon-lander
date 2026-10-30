process.stderr.write('BINARY_STDERR\n' + JSON.stringify(process.argv.slice(2)) + '\n');
process.stdin.pipe(process.stdout);
process.stdin.once('end', () => { process.exitCode = 23; });
