Feature: Inspect optional capabilities in a mixed cell collection
  Unsupported lookup is distinct from supported lookup without a match.

  Scenario: Inspect Jupyter and DIB cells through the same cell interface
    Given cells from the Jupyter notebook:
      """json
      {"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[
        {"id":"plot","cell_type":"markdown","metadata":{},"source":"plot","attachments":{"plot.png":{"image/png":"YWJj"}}},
        {"id":"empty","cell_type":"code","metadata":{},"source":"print(1)","execution_count":null,"outputs":[]},
        {"id":"future","cell_type":"future","metadata":{},"custom":"uninterpreted"}]}
      """
    And cells from the DIB notebook:
      """dib
      #!markdown
      # Plain text
      #!csharp
      Console.WriteLine(1);
      """
    When I inspect the mixed cells for MIME type "image/png"
    Then the MIME inspection results are "matched,no match,no match,unsupported,unsupported"
    When I inspect the mixed cells for MIME type "application/json"
    Then the MIME inspection results are "no match,no match,no match,unsupported,unsupported"
