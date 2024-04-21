import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/regex
import gleam/result.{try}
import gleam/string
import simplifile
import startest/context.{type Context}
import startest/logger
import startest/test_case.{type Test, Test}
import startest/test_tree.{type TestTree, decode_test_tree}

/// A file in the `test/` directory that likely contains tests.
pub type TestFile {
  TestFile(
    /// The filepath to the `.gleam` file.
    filepath: String,
    /// The name of the Gleam module.
    module_name: String,
  )
}

/// Returns the list of files in the `test/` directory.
pub fn locate_test_files() -> Result(List(TestFile), Nil) {
  use test_files <- try(
    simplifile.get_files(in: "test")
    |> result.nil_error,
  )

  test_files
  |> list.filter(fn(filepath) { string.ends_with(filepath, ".gleam") })
  |> list.map(fn(filepath) {
    let module_name = filepath_to_module_name(filepath)
    TestFile(filepath, module_name)
  })
  |> Ok
}

/// Returns the Gleam module name from the given filepath.
fn filepath_to_module_name(filepath: String) -> String {
  filepath
  |> string.slice(
    at_index: string.length("test/"),
    length: string.length(filepath),
  )
  |> string.replace(".gleam", "")
}

pub type NamedFunction =
  #(String, fn() -> Dynamic)

pub fn identify_tests(
  test_functions: List(NamedFunction),
  ctx: Context,
) -> List(TestTree) {
  let #(standalone_tests, test_functions) =
    test_functions
    |> list.partition(is_standalone_test(_, ctx))
  let standalone_tests =
    standalone_tests
    |> list.map(fn(named_fn) {
      let #(function_name, function) = named_fn

      let function: fn() -> Nil =
        function
        |> dynamic.from
        |> dynamic.unsafe_coerce

      Test(function_name, function, False)
      |> test_tree.Test
    })

  let #(test_suites, _test_functions) =
    test_functions
    |> list.partition(is_test_suite(_, ctx))
  let test_suites =
    test_suites
    |> list.filter_map(fn(named_fn) {
      let #(_function_name, function) = named_fn

      let value = function()

      decode_test_tree(value)
      |> result.map_error(fn(error) {
        logger.error(ctx.logger, string.inspect(error))
      })
    })

  list.concat([test_suites, standalone_tests])
}

fn is_standalone_test(named_fn: NamedFunction, ctx: Context) -> Bool {
  let #(function_name, _) = named_fn

  function_name
  |> regex.check(with: ctx.config.discover_standalone_tests_pattern)
}

fn is_test_suite(named_fn: NamedFunction, ctx: Context) -> Bool {
  let #(function_name, _) = named_fn

  function_name
  |> regex.check(with: ctx.config.discover_describe_tests_pattern)
}
