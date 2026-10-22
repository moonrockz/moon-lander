// Independent artifact oracle: validate each corpus document against its
// version's frozen OpenRPC schema with pinned Ajv and local resources only.
import Ajv from "ajv";
import { readFileSync } from "node:fs";

const [assets, corpus] = process.argv.slice(2);
const read = (path) => JSON.parse(readFileSync(path, "utf8"));
const ajv = new Ajv({
  meta: false,
  validateSchema: false,
  validateFormats: false,
  strict: false,
  allErrors: true,
});
const draft07 = read(`${assets}/draft-07-schema.json`);
ajv.addMetaSchema(draft07);
ajv.addSchema(read(`${assets}/json-schema-meta.json`));
ajv.addSchema(read(`${assets}/json-schema-meta-alias.json`), "https://meta.json-schema.tools");
const schemas = {
  "1.3.2": read(`${assets}/open-rpc-meta-schema.json`),
  "1.4": read(`${assets}/openrpc-1.4-schema.json`),
};
const validators = {};
for (const [line, schema] of Object.entries(schemas)) {
  const { $id, ...rest } = schema;
  validators[line] = ajv.compile(rest);
}
const cases = read(`${corpus}/cases.json`);
const results = cases.map(({ id }) => {
  const document = read(`${corpus}/${id}.json`);
  const line = document.openrpc === "1.3.2" ? "1.3.2" : "1.4";
  return [id, Boolean(validators[line](document))];
});
console.log(JSON.stringify(results));
