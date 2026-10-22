///|
/// Headless hosted-configuration example. The caller supplies its authorized
/// directory base. No fetch, UI, or ambient configuration runs at module import.
struct Server { host : String; port : Int } derive(FromJson)

///|
async fn hosted(base : String) -> String {
  let mount = @browser.from_urls(base, { "version": 1, "files": ["acme.toml"] }, root="/workspace")
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.file("acme.toml")
    |> @config.overrides([("server.port", @config.int(9000))])
  let controller = @browser.AbortController::new()
  let config = @browser.load(builder, [mount], signal=controller.signal())
  let server : Server = @config.bind(config, "server")
  "\{server.host}:\{server.port}"
}

///|
/// The files of an HTML file input, as the application received them.
#external
priv type FileList

///|
extern "js" fn FileList::length(self : FileList) -> Int =
  #|files => files.length

///|
extern "js" fn FileList::at(self : FileList, index : Int) -> @browser.File =
  #|(files, index) => files[index]

///|
/// Map selected files to explicit relative paths. A plain file input gives only
/// `File.name`. A directory input gives `webkitRelativePath` with the selected
/// directory as its first segment; this application chooses to remove it.
fn project_files(list : FileList) -> Array[(String, @browser.File)] {
  let files = []
  for i = 0; i < list.length(); i = i + 1 {
    let file = list.at(i)
    let relative = match file.webkit_relative_path() {
      "" => file.name()
      path =>
        match path.find("/") {
          Some(index) => path[index + 1:].to_owned()
          None => path
        }
    }
    files.push((relative, file))
  }
  files
}

///|
/// Merge hosted defaults with selected project files. The builder order gives
/// the precedence: the project file overrides the hosted defaults.
async fn selected(files : FileList, base : String) -> String {
  let defaults = @browser.from_urls(base, { "version": 1, "files": ["acme.toml"] }, root="/defaults")
  let project = @browser.from_files(project_files(files), root="/workspace")
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.file("/defaults/acme.toml")
    |> @config.working_dir("/workspace/src")
    |> @conventions.add(@browser.workspace(@conventions.app_dirs("acme"), project))
  let config = @browser.load(builder, [defaults, project])
  let server : Server = @config.bind(config, "server")
  let origin = config.origins(@config.KeyPath::parse("server.host"))[0].location.unwrap_or("none")
  "\{server.host}:\{server.port} from \{origin}"
}

///|
extern "js" fn expose(
  load : (String) -> @js_async.Promise[String],
  load_selected : (FileList, String) -> @js_async.Promise[String],
) -> Unit =
  #|(load, loadSelected) => {
  #|  globalThis.loadHostedServer = load;
  #|  globalThis.loadSelectedServer = loadSelected;
  #|}

///|
fn main {
  expose(base => @js_async.Promise::from_async(() => hosted(base)), (files, base) => @js_async.Promise::from_async(() => selected(files, base)))
}
