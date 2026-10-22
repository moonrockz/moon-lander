import Ajv from "ajv";

const metaschema = JSON.parse(process.argv[2]);
const cases = JSON.parse(process.argv[3]);
const ajv = new Ajv({
  meta: false,
  validateSchema: false,
  validateFormats: false,
  strict: false,
  allErrors: true,
});
ajv.addMetaSchema(metaschema);
const validate = ajv.getSchema(metaschema.$id);
if (!validate) throw new Error("Frozen draft-07 metaschema was not registered");
console.log(JSON.stringify(cases.map(({ schema }) => Boolean(validate(schema)))));
