// Independent behavior payload; only used by this ruleset's development tests.
package main

import (
 "encoding/json"
 "fmt"
 "os"
 "os/exec"
 "path/filepath"
 "strconv"
 "strings"
 "syscall"
 "time"
)

func main() {
 args := os.Args[1:]
 if len(args) > 0 && args[0] == "--child" { fmt.Println("child-ok"); return }
 if len(args) > 0 && args[0] == "--exit" { n, _ := strconv.Atoi(args[1]); os.Exit(n) }
 if len(args) > 0 && args[0] == "--sleep" { time.Sleep(300*time.Second); return }
 if len(args) > 0 && args[0] == "--dll" {
  dll, err := syscall.LoadDLL(filepath.Join(filepath.Dir(os.Args[0]), "companion.dll")); if err != nil { panic(err) }; defer dll.Release()
  proc, err := dll.FindProc("answer"); if err != nil { panic(err) }; result, _, _ := proc.Call(); if result != 42 { panic(result) }; args = args[1:]
 }
 exe, _ := os.Executable()
 child := exec.Command(exe, "--child"); data, err := child.CombinedOutput(); if err != nil || strings.TrimSpace(string(data)) != "child-ok" { panic(fmt.Sprintf("child: %s %v", data, err)) }
 cwd, _ := os.Getwd()
 env := map[string]string{}
 for _, key := range []string{"WINEPREFIX", "TEST_TMPDIR", "TEST_SRCDIR", "RUNFILES_DIR", "XML_OUTPUT_FILE", "TEST_SHARD_INDEX", "TEST_TOTAL_SHARDS", "FIXTURE_VALUE"} { env[key] = os.Getenv(key) }
 record := map[string]any{"args": args, "cwd": cwd, "env": env, "child": "child-ok"}
 if path := os.Getenv("TEST_SHARD_STATUS_FILE"); path != "" { if err := os.WriteFile(path, []byte("sharding supported\n"), 0600); err != nil { panic(err) } }
 if dir := os.Getenv("TEST_TMPDIR"); dir != "" { if err := os.WriteFile(filepath.Join(dir, "fixture.tmp"), []byte("temporary\n"), 0600); err != nil { panic(err) } }
 if xml := os.Getenv("XML_OUTPUT_FILE"); xml != "" { if err := os.WriteFile(xml, []byte(`<testsuites><testsuite name="wine" tests="1"><testcase name="fixture"/></testsuite></testsuites>`), 0600); err != nil { panic(err) } }
 encoded, _ := json.MarshalIndent(record, "", "  ")
 if len(args) > 0 && args[0] == "--output" { if err := os.WriteFile(args[1], encoded, 0600); err != nil { panic(err) } } else { fmt.Println(string(encoded)) }
}
