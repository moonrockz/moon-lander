Feature: Navigate notebooks through common and specialized APIs
  Shared traversal keeps each format's concrete nodes available to callers.

  Scenario: Read YAML metadata with custom kernel aliases
    Given the DIB source:
      """dib
      #!meta yaml
      title: YAML example
      kernelInfo:
        defaultKernelName: custom
        items:
          - name: custom
            aliases: [alt]
      #!alt
      run()
      """
    When the notebook is parsed
    Then the common notebook metadata title is "YAML example"
    And the common cell kinds are "code"
    And the custom kernel alias finds source "run()"
    And the DIB source round-trips

  Scenario: Read TOML metadata and retain its timestamp type
    Given the DIB source:
      """dib
      #!meta toml
      title = "TOML example"
      created = 2026-10-19T12:30:00Z
      [kernelInfo]
      defaultKernelName = "custom"
      [[kernelInfo.items]]
      name = "custom"
      aliases = ["alt"]
      #!alt
      run()
      """
    When the notebook is parsed
    Then the common notebook metadata title is "TOML example"
    And the metadata field "created" has Ion type "timestamp"
    And the custom kernel alias finds source "run()"
    And the DIB source round-trips

  Scenario: Read native Ion metadata without losing decimal precision
    Given the DIB source:
      """dib
      #!meta ion
      {title: "Ion example", amount: 12345678901234567890.500, missing: null.int}
      #!csharp
      run()
      """
    When the notebook is parsed
    Then the common notebook metadata title is "Ion example"
    And the metadata field "amount" has Ion type "decimal"
    And the metadata field "missing" has Ion type "int"
    And the DIB source round-trips

  Scenario: Navigate a polyglot DIB notebook and inspect its directives
    Given the DIB source:
      """dib
      #!meta
      {"title":"Polyglot","kernelInfo":{"defaultKernelName":"csharp","items":[{"name":"custom","aliases":["alt"]}]}}
      #!md
      # Results
      #!c#
      #!share --from fsharp x
      Console.WriteLine(x);
      #!alt
      example()
      """
    When the notebook is parsed
    Then the common notebook metadata title is "Polyglot"
    And the common cell kinds are "markdown,code,code"
    And common cursor paths resolve to their concrete nodes
    And the specialized directive is "share" with arguments "--from fsharp x"
    And the custom kernel alias finds source "example()"
    And the DIB source round-trips

  Scenario: Navigate a Jupyter notebook and inspect its outputs
    Given the Jupyter JSON:
      """json
      {"nbformat":4,"nbformat_minor":5,"metadata":{"title":"Jupyter"},"cells":[
        {"id":"intro","cell_type":"markdown","metadata":{},"source":"# Results","attachments":{"plot.png":{"image/png":"YWJj"}}},
        {"id":"calculation","cell_type":"code","metadata":{},"source":"1 + 1","execution_count":1,"outputs":[{"output_type":"stream","name":"stdout","text":"2"}]}]}
      """
    When the notebook is parsed
    Then the common notebook metadata title is "Jupyter"
    And the common cell kinds are "markdown,code"
    And common cursor paths resolve to their concrete nodes
    And specialized Jupyter navigation finds the stream and attachment

  Scenario: Keep executable directives inside their cell
    Given the DIB source:
      """dib
      #!csharp
      #!connect named-pipe --kernel-name external
      #!external -h
      #!fsharp
      let x = 1
      """
    When the notebook is parsed
    Then the common cell kinds are "code,code"
    And common cursor paths resolve to their concrete nodes
    And the first DIB cell has 2 directives
