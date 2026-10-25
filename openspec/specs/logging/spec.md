# logging Specification

## Purpose
Give MoonBit applications and libraries one logging abstraction, in the style of
.NET `Microsoft.Extensions.Logging` and Serilog. Library code writes structured
events through it, and the application brings the backend that receives them.

## Requirements

### Requirement: Bring-your-own logger
The root package of the logging module SHALL define one public open trait that any package can
implement to receive log events. The trait SHALL have one required operation that
receives an event and one level check with a default that enables all levels. A
value of a type that implements the trait SHALL be usable everywhere the package
accepts a logger, the same as a built-in logger.

#### Scenario: Application logger receives events
- **WHEN** an application defines its own type that implements only the required operation, and writes an `Information` event through a value of that type
- **THEN** the application type receives that event with its level, template, and property values unchanged

#### Scenario: Default level check enables all levels
- **WHEN** an application logger does not implement the level check, and code writes one event at each of the six levels
- **THEN** the application logger receives six events

#### Scenario: Library code does not know the backend
- **WHEN** a library function takes a logger value and writes an event, and a test calls it one time with an application logger and one time with the in-memory logger
- **THEN** each logger receives the same event

### Requirement: Log levels
The package SHALL define six log levels in this order, from lowest to highest:
`Trace`, `Debug`, `Information`, `Warning`, `Error`, `Critical`. Levels SHALL
compare by this order.

#### Scenario: Level order
- **WHEN** a test compares `Debug` with `Warning`, and `Critical` with `Error`
- **THEN** `Debug` is lower than `Warning`, and `Critical` is higher than `Error`

### Requirement: Level methods
The package SHALL give one method for each level on a logger value. Each method
SHALL take a message template, positional argument values, and an optional error,
and SHALL write one event at its level.

#### Scenario: Warning method writes a warning event
- **WHEN** code calls the warning method with the template `"Disk {Name} is low"` and the argument `"C"`
- **THEN** the logger receives one event with level `Warning`, template `"Disk {Name} is low"`, and property `Name` equal to the text `"C"`

#### Scenario: Error method keeps the error value
- **WHEN** code calls the error method with the template `"Load failed"`, no arguments, and an application error value
- **THEN** the event holds that error value, and the event has no properties

### Requirement: Level check before event construction
A level method SHALL ask the logger whether its level is enabled before it parses
the template or builds an event. For a disabled level, the method SHALL not parse
the template, SHALL not build an event, and SHALL not call the receive operation.

#### Scenario: Disabled level builds no event
- **WHEN** an application logger enables only `Warning` and higher, counts each call to its receive operation, and code calls the debug method
- **THEN** the receive operation count stays zero

#### Scenario: Enabled level builds the event
- **WHEN** the same application logger gets a call to the error method
- **THEN** the receive operation count becomes one

### Requirement: Structured log events
A log event SHALL be an immutable value that holds the level, an optional
category, the message template text, the property values as an ordered list of
name and value pairs, and an optional error. Property values SHALL be structured
JSON values, not text.

#### Scenario: Event keeps a number as a number
- **WHEN** code writes the template `"Loaded {Count} files"` with the argument `3`
- **THEN** the event property `Count` is the JSON number 3, not the text `"3"`

#### Scenario: Event keeps a nested value
- **WHEN** code writes the template `"Saved {Order}"` with a JSON object argument that holds the fields `id` and `total`
- **THEN** the event property `Order` is the same JSON object with both fields

#### Scenario: A change to the read properties does not change the event
- **WHEN** a reader of a kept event removes all its properties, and changes a JSON object in a property value
- **THEN** the next read of the same event gives the original properties and the original message

#### Scenario: A change to an argument does not change the event
- **WHEN** code writes the template `"Saved {Items}"` with a JSON array argument `[1, 2]`, and then adds `3` to that array
- **THEN** the message of the kept event is `"Saved [1,2]"`

### Requirement: Message template binding
The package SHALL bind the positional arguments to the named holes of a template
in order of appearance. A hole is a name in braces. A doubled brace (`{{` or `}}`)
SHALL be a literal brace and not a hole. The bound properties SHALL be in hole
order.

#### Scenario: Two holes bind in order
- **WHEN** code writes the template `"Loaded {Count} files from {Path}"` with the arguments `3` and `"src"`
- **THEN** the event properties are `Count` equal to 3 and then `Path` equal to `"src"`

#### Scenario: Escaped braces are not holes
- **WHEN** code writes the template `"Use {{Name}} for {Value}"` with the argument `7`
- **THEN** the event has one property, `Value` equal to 7, and the rendered message is `"Use {Name} for 7"`

### Requirement: Template mismatches do not fail
A template or argument mismatch SHALL not raise an error and SHALL not drop the
event. A hole without an argument SHALL stay as its literal text in the rendered
message and SHALL give no property. An argument without a hole SHALL not appear in
the properties. A malformed hole, such as an unclosed brace or an empty name,
SHALL be literal text.

#### Scenario: Missing argument
- **WHEN** code writes the template `"From {Path} to {Target}"` with only the argument `"a"`
- **THEN** the event has one property, `Path` equal to `"a"`, and the rendered message is `"From a to {Target}"`

#### Scenario: Extra argument
- **WHEN** code writes the template `"Done {Count}"` with the arguments `1` and `2`
- **THEN** the event has one property, `Count` equal to 1, and the rendered message is `"Done 1"`

#### Scenario: Unclosed brace
- **WHEN** code writes the template `"Value {Name"` with the argument `5`
- **THEN** the event has no properties, and the rendered message is `"Value {Name"`

### Requirement: Message rendering
The package SHALL render the message text of an event by putting each bound
property value in place of its hole. A JSON string value SHALL render as its text
without quotes. Each other JSON value SHALL render as its compact JSON text.

#### Scenario: String and number values
- **WHEN** the package renders an event with the template `"Loaded {Count} files from {Path}"` and the properties `Count` equal to 3 and `Path` equal to `"src"`
- **THEN** the message text is `"Loaded 3 files from src"`

#### Scenario: Object value
- **WHEN** the package renders an event with the template `"Saved {Order}"` and the property `Order` equal to the JSON object with `id` equal to 1
- **THEN** the message text is `"Saved {\"id\":1}"`

### Requirement: Text line rendering
The package SHALL render an event as one text line: a three-letter level code in
brackets, then the category and a colon when the event has a category, then the
message text. The level codes SHALL be `TRC`, `DBG`, `INF`, `WRN`, `ERR`, and
`CRT`. When the event has an error, the package SHALL add the error text on a
second line.

#### Scenario: Line with a category
- **WHEN** the package renders an `Information` event with category `"morphir.build"` and message text `"Loaded 3 files from src"`
- **THEN** the line is `"[INF] morphir.build: Loaded 3 files from src"`

#### Scenario: Line without a category
- **WHEN** the package renders a `Warning` event with no category and message text `"Disk C is low"`
- **THEN** the line is `"[WRN] Disk C is low"`

#### Scenario: Line with an error
- **WHEN** the package renders an `Error` event with no category, message text `"Load failed"`, and an error whose text is `"NotFound"`
- **THEN** the result is `"[ERR] Load failed"`, a line break, and `"  error: NotFound"`

### Requirement: Null logger
The package SHALL give a logger that disables all levels and drops each event.

#### Scenario: Null logger drops events
- **WHEN** code writes a `Critical` event to the null logger
- **THEN** no error occurs and no other logger receives the event

### Requirement: In-memory logger
The package SHALL give an in-memory logger that keeps each event it receives, in
receive order, and lets a test read the kept events.

#### Scenario: Events kept in order
- **WHEN** code writes an `Information` event and then a `Warning` event to an in-memory logger
- **THEN** the in-memory logger gives two events, the `Information` event first

### Requirement: Minimum level filter
The package SHALL give a combinator that wraps a logger with a minimum level. The
wrapper SHALL enable a level only when the level is equal to or higher than the
minimum and the wrapped logger enables it. The wrapper SHALL pass only enabled
events to the wrapped logger.

#### Scenario: Lower levels are dropped
- **WHEN** an in-memory logger is wrapped with minimum level `Warning`, and code writes one event at each of the six levels through the wrapper
- **THEN** the in-memory logger holds three events, at `Warning`, `Error`, and `Critical`

#### Scenario: Wrapped logger can disable more
- **WHEN** an application logger that enables only `Error` and higher is wrapped with minimum level `Debug`, and code writes a `Warning` event through the wrapper
- **THEN** the application logger receives no event

### Requirement: Fan-out logger
The package SHALL give a combinator that sends each event to a list of loggers, in
list order. The fan-out SHALL enable a level when any logger in the list enables
it, and SHALL give each event only to the loggers that enable its level.

#### Scenario: Two loggers receive one event
- **WHEN** a fan-out holds two in-memory loggers and code writes one `Information` event
- **THEN** each in-memory logger holds that one event

#### Scenario: Each logger keeps its own level
- **WHEN** a fan-out holds an in-memory logger and a second in-memory logger wrapped with minimum level `Error`, and code writes a `Warning` event
- **THEN** the first logger holds the event and the second logger holds no event

### Requirement: Category wrapper
The package SHALL give a combinator that wraps a logger with a category name. The
wrapper SHALL set that category on each event that it passes on, and SHALL not
change the other fields of the event.

#### Scenario: Category is set
- **WHEN** an in-memory logger is wrapped with category `"morphir.build"`, and code writes an `Information` event through the wrapper
- **THEN** the kept event has category `"morphir.build"` and the same level, template, and properties

### Requirement: Logging never fails the caller
No operation of the logging package SHALL raise an error to the code that writes
an event. The receive operation of the logger trait SHALL not be able to raise.

#### Scenario: Write has no error path
- **WHEN** a test reads the generated public interface of the package
- **THEN** no level method and no receive operation has a `raise` effect

### Requirement: Same behavior on all targets
The root package of the logging module SHALL have the same public interface and the
same behavior on `wasm`, `wasm-gc`, `js`, and `native`. It SHALL use only the
MoonBit core library, and SHALL do no I/O.

#### Scenario: Suite runs on each target
- **WHEN** the logging acceptance suite runs on each of the four targets
- **THEN** each target runs more than zero logging tests and all of them pass

#### Scenario: Interface is the same on each target
- **WHEN** the generated public interface of the package is made for each of the four targets
- **THEN** the four interfaces are the same
