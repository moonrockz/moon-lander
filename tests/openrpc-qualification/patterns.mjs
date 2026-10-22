import { RegExpValidator } from "@eslint-community/regexpp";

const cases = JSON.parse(process.argv[2]);
const validator = new RegExpValidator({ ecmaVersion: 2018, strict: false });
const results = cases.map(({ pattern }) => {
  try {
    validator.validatePattern(pattern, 0, pattern.length, { unicode: false });
    return true;
  } catch (error) {
    if (!(error instanceof SyntaxError)) throw error;
    return false;
  }
});
console.log(JSON.stringify(results));
