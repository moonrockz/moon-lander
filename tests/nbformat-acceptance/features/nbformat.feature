Feature: Represent and navigate Jupyter notebooks
  A notebook retains its cells, outputs, attachments and custom information.
  Reading validates required fields without executing any notebook code.

  Scenario: Read and navigate a notebook with rich outputs and attachments
    Given the notebook JSON:
      """json
      {"nbformat":4,"nbformat_minor":5,"metadata":{"language_info":{"name":"python"}},"cells":[
        {"id":"intro","cell_type":"markdown","metadata":{},"source":["# Results\n","An image"],"attachments":{"plot.png":{"image/png":["YW","Jj"]}}},
        {"id":"code","cell_type":"code","metadata":{},"source":"1 + 1","execution_count":1,"outputs":[
          {"output_type":"stream","name":"stdout","text":["hello\n","world"]},
          {"output_type":"execute_result","execution_count":1,"metadata":{},"data":{"text/plain":["2"],"application/json":{"answer":2}}}]},
        {"id":"raw","cell_type":"raw","metadata":{"format":"text/latex"},"source":"\\alpha"}]}
      """
    When the notebook is read
    Then the cell types are "markdown,code,raw"
    And the first cell source is "# Results\nAn image"
    And the attachment contains "YWJj"
    And the code outputs are "stream,execute_result"
    And the cells containing MIME type "image/png" have IDs "intro"
    And the cells containing MIME type "application/json" have IDs "code"
    And the cells containing MIME type "image/jpeg" have IDs ""
    And cursor paths resolve to the visited nodes
    And writing and reading preserves the notebook

  Scenario: Read an older notebook without cell IDs
    Given the notebook JSON:
      """json
      {"nbformat":4,"nbformat_minor":0,"metadata":{},"cells":[{"cell_type":"raw","metadata":{},"source":[]}]}
      """
    When the notebook is read
    Then the cell types are "raw"
    And writing and reading preserves the notebook

  Scenario: Preserve extensions from a future minor version
    Given the notebook JSON:
      """json
      {"nbformat":4,"nbformat_minor":9,"metadata":{"vendor":{"nested":[true]}},"extension":{"payload":[1,2]},"cells":[
        {"id":"future","cell_type":"diagram","metadata":{},"diagram":{"nodes":["a","b"]}},
        {"id":"code","cell_type":"code","metadata":{},"source":"","execution_count":null,"outputs":[{"output_type":"widget","state":{"values":[1,2]}}]}]}
      """
    When the notebook is read
    Then the cell types are "diagram,code"
    And cursor paths resolve to the visited nodes
    And writing and reading preserves the notebook
    And future payloads are retained

  Scenario: Report the location of invalid notebook data
    Given the notebook JSON:
      """json
      {"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[{"id":"a","cell_type":"code","metadata":{},"source":"","execution_count":null,"outputs":[{"output_type":"stream","name":"stdout","text":[1]}]}]}
      """
    When the notebook is read
    Then the invalid field is "$.cells[0].outputs[0].text[0]"

  Scenario: Reject duplicate cell IDs
    Given the notebook JSON:
      """json
      {"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[{"id":"same","cell_type":"raw","metadata":{},"source":""},{"id":"same","cell_type":"markdown","metadata":{},"source":""}]}
      """
    When the notebook is read
    Then the duplicate cell ID is "same"
