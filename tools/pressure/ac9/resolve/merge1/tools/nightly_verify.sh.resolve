# tools/list_report.sh's report at the end of this run must not be fooled by
# a stale logs/runs/* directory left over from some earlier, unrelated
# experiment (a deliberately narrowed cap, a probe build) -- that directory's
# truncation line is not a defect in the tree this run is measuring. So this
# run touches a marker here, the moment it starts running checks, in the same
# $LOG_DIR it already keeps its own check logs in, and hands it to
# list_report.sh as --since: only a run directory this run's own checks
# create (mtime after this marker) counts toward the report below.
mkdir -p "$LOG_DIR" 2> /dev/null
LIST_REPORT_SINCE="$LOG_DIR/list-report-since.marker"
: > "$LIST_REPORT_SINCE" 2> /dev/null

# Hold the characters fixed: a fixture the base pinned loads from the entry the
# base binary built, whatever this tree's binary and module now are. A caller
# that already set INCURSION_FIXTURE_PIN keeps its own.
if [ -z "${INCURSION_FIXTURE_PIN:-}" ] && [ -r "$FIXTURE_PIN_RECORD" ]; then
    export INCURSION_FIXTURE_PIN="$FIXTURE_PIN_RECORD"
    echo "fixture pins: the checks load the characters the base built ($FIXTURE_PIN_RECORD)"
fi

