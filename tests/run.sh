#!/bin/sh
# Runs Nahr's tests with `sultanc test`, then builds every example.
#
#   SULTANC_ROOT=/path/to/sultanc-repo tests/run.sh
#
# The tests are the @@اختبار (@@test) functions of the modules tests/tests.sn
# imports: one build, and each test in its own process. SULTANC_ROOT is the
# compiler checkout; SULTANC defaults to $SULTANC_ROOT/build/sultanc.
#
#   NAHR_INTERP=1          runs the tests in the interpreter, and checks the
#                          examples instead of building them
#   NAHR_TEST_FILTER=text  runs only the tests whose name contains text
set -u
tests_dir=$(cd "$(dirname "$0")" && pwd)
: "${SULTANC_ROOT:?set SULTANC_ROOT to the SultanC repository}"
compiler=${SULTANC:-$SULTANC_ROOT/build/sultanc}
# The compiler does not read Supax.toml; these graphs (tools/package_graphs.py)
# say where the nahr package is.
tests_graph=$tests_dir/package-graph.toml
examples_graph=$tests_dir/../examples/package-graph.toml
out_dir=${NAHR_TEST_OUT:-$(mktemp -d)}
status=0

# ———— tests ————
set -- test --package-graph "$tests_graph"
[ "${NAHR_INTERP:-0}" = 1 ] && set -- "$@" --interpret
[ -n "${NAHR_TEST_FILTER:-}" ] && set -- "$@" --filter "$NAHR_TEST_FILTER"
(cd "$SULTANC_ROOT" && "$compiler" "$@" "$tests_dir/tests.sn") || status=1

# ———— examples: built, not run (they start a server) ————
echo
built=0
broken=0
for source in "$tests_dir"/../examples/ar/*.sn "$tests_dir"/../examples/en/*.sn; do
    lang=$(basename "$(dirname "$source")")
    name="example-$lang-$(basename "$source" .sn)"
    source=$(cd "$(dirname "$source")" && pwd)/$(basename "$source")
    if [ "${NAHR_INTERP:-0}" = 1 ]; then
        what=checked
        (cd "$SULTANC_ROOT" && "$compiler" check --package-graph "$examples_graph" "$source") > "$out_dir/$name.log" 2>&1
    else
        what=built
        (cd "$SULTANC_ROOT" && "$compiler" "$source" --package-graph "$examples_graph" -o "$out_dir/$name") > "$out_dir/$name.log" 2>&1 \
            && [ -x "$out_dir/$name" ]
    fi
    if [ $? = 0 ]; then
        echo "ok   $name ($what)"; built=$((built + 1))
    else
        echo "FAIL $name"; sed -n '1,20p' "$out_dir/$name.log"; broken=$((broken + 1)); status=1
    fi
done
echo "examples: $built $what, $broken failed"
exit $status
