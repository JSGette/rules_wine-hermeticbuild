// Development-only real-runtime integration harness; no mocked Wine lifecycle.
package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"syscall"
	"time"
)

type config struct {
	Launcher, Loader, Server, Payload, WrongArch, WrongLoader string
	AdapterCLI                                                bool
}
type record struct {
	Args  []string
	Child string
	Env   map[string]string
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}
func locate(path string) string {
	return filepath.Join(os.Getenv("TEST_SRCDIR"), filepath.FromSlash(path))
}
func read(path string) record {
	data, err := os.ReadFile(path)
	must(err)
	var r record
	must(json.Unmarshal(data, &r))
	return r
}
func verifyAdapterCLI(c config, dir string) {
	adapter := filepath.Join(dir, "adapter")
	must(os.Symlink(c.Launcher, adapter))
	content, err := json.Marshal(map[string]any{"backend": "wine", "arch": "x86_64", "loader": c.Loader, "server": c.Server, "payload": c.Payload})
	must(err)
	must(os.WriteFile(adapter+".json", content, 0600))
	failures := []string{}
	for index, prefix := range [][]string{{"--config", "payload-config.json"}, {"--", "literal"}} {
		output := filepath.Join(dir, fmt.Sprintf("adapter-%d.json", index))
		args := append(append([]string{}, prefix...), "--output", "{windows_path:"+output+"}")
		runContext, cancel := context.WithTimeout(context.Background(), 75*time.Second)
		cmd := exec.CommandContext(runContext, adapter, args...)
		cmd.Env = append(os.Environ(), "XML_OUTPUT_FILE=", "TEST_SHARD_STATUS_FILE=")
		log, err := cmd.CombinedOutput()
		cancel()
		if err != nil {
			failures = append(failures, fmt.Sprintf("prefix %q: %v\n%s", prefix, err, log))
			continue
		}
		actual := read(output).Args
		if len(actual) < len(prefix) || !reflect.DeepEqual(actual[:len(prefix)], prefix) {
			failures = append(failures, fmt.Sprintf("prefix %q became %q", prefix, actual))
		}
	}
	if len(failures) > 0 {
		panic(strings.Join(failures, "\n"))
	}
	fmt.Println("PASS: adapter forwards leading --config and literal -- exactly; adjacent configuration remains authoritative")
}

func main() {
	data, err := os.ReadFile(os.Args[0] + ".json")
	must(err)
	var c config
	must(json.Unmarshal(data, &c))
	c.Launcher, c.Loader, c.Server, c.Payload, c.WrongArch, c.WrongLoader = locate(c.Launcher), locate(c.Loader), locate(c.Server), locate(c.Payload), locate(c.WrongArch), locate(c.WrongLoader)
	originalPayload, err := os.ReadFile(c.Payload)
	must(err)
	originalLoader, err := os.ReadFile(c.Loader)
	must(err)
	dir, err := os.MkdirTemp(os.Getenv("TEST_TMPDIR"), "contract-")
	must(err)
	defer os.RemoveAll(dir)
	if c.AdapterCLI {
		verifyAdapterCLI(c, dir)
		return
	}
	count := 0
	launch := func(payload string, args []string) (*exec.Cmd, *bytes.Buffer) {
		count++
		name := filepath.Join(dir, fmt.Sprintf("invocation-%d.json", count))
		value := map[string]any{"backend": "wine", "arch": "x86_64", "loader": c.Loader, "server": c.Server, "payload": payload, "args": args}
		content, _ := json.Marshal(value)
		must(os.WriteFile(name, content, 0600))
		cmd := exec.Command(c.Launcher, "--config", name)
		cmd.Env = os.Environ()
		// This harness is a Bazel test; its nested Windows processes are not tests.
		// Avoid racing their writes to this harness's XML and shard files.
		for _, key := range []string{"XML_OUTPUT_FILE", "TEST_SHARD_STATUS_FILE"} {
			cmd.Env = append(cmd.Env, key+"=")
		}
		log := new(bytes.Buffer)
		cmd.Stdout, cmd.Stderr = log, log
		must(cmd.Start())
		return cmd, log
	}
	// Verify concurrent sessions, writable isolation and cancellation ownership.
	output1, output2 := filepath.Join(dir, "first.json"), filepath.Join(dir, "second.json")
	first, log1 := launch(c.Payload, []string{"--output", "{windows_path:" + output1 + "}", "--isolated", "--hold"})
	second, log2 := launch(c.Payload, []string{"--output", "{windows_path:" + output2 + "}", "--isolated", "--hold"})
	waitFile := func(path string) {
		deadline := time.Now().Add(75 * time.Second)
		for time.Now().Before(deadline) {
			if _, err := os.Stat(path); err == nil {
				return
			}
			time.Sleep(50 * time.Millisecond)
		}
		panic(fmt.Sprintf("fixture output missing: %s\n%s\n%s", path, log1, log2))
	}
	waitFile(output1)
	waitFile(output2)
	one, two := read(output1), read(output2)
	prefix1, prefix2 := one.Env["WINEPREFIX"], two.Env["WINEPREFIX"]
	if prefix1 == "" || prefix2 == "" || prefix1 == prefix2 || one.Child != "child-ok" || two.Child != "child-ok" {
		panic("private prefix/child contract")
	}
	cancel := func(cmd *exec.Cmd, prefix string, log *bytes.Buffer) {
		must(cmd.Process.Signal(syscall.SIGTERM))
		done := make(chan error, 1)
		go func() { done <- cmd.Wait() }()
		select {
		case err := <-done:
			if err == nil {
				panic("cancellation unexpectedly succeeded")
			}
		case <-time.After(15 * time.Second):
			_ = cmd.Process.Kill()
			panic("supervisor did not terminate on cancellation")
		}
		if _, err := os.Stat(filepath.Dir(prefix)); !os.IsNotExist(err) {
			panic(fmt.Sprintf("scratch not cleaned: %s %v\n%s", prefix, err, log))
		}
		entries, _ := os.ReadDir("/proc")
		for _, entry := range entries {
			env, _ := os.ReadFile("/proc/" + entry.Name() + "/environ")
			if bytes.Contains(env, []byte("WINEPREFIX="+prefix+"\x00")) {
				panic("owned descendant survived: " + entry.Name())
			}
		}
	}
	cancel(first, prefix1, log1)
	if err := second.Process.Signal(syscall.Signal(0)); err != nil {
		panic("cancelling first terminated independent second invocation")
	}
	cancel(second, prefix2, log2)
	cmd, log := launch(c.Payload, []string{"--exit", "37"})
	err = cmd.Wait()
	if exit, ok := err.(*exec.ExitError); !ok || exit.ExitCode() != 37 {
		panic(fmt.Sprintf("exit-code contract: %v\n%s", err, log))
	}
	cmd, log = launch(c.WrongArch, nil)
	err = cmd.Wait()
	if exit, ok := err.(*exec.ExitError); !ok || exit.ExitCode() != 125 || !strings.Contains(log.String(), "machine does not match") {
		panic(fmt.Sprintf("wrong-CPU rejection: %v\n%s", err, log))
	}
	oldLoader := c.Loader
	c.Loader = c.WrongLoader
	cmd, log = launch(c.Payload, nil)
	err = cmd.Wait()
	if exit, ok := err.(*exec.ExitError); !ok || exit.ExitCode() != 125 || !strings.Contains(log.String(), "Wine executable CPU does not match") {
		panic(fmt.Sprintf("wrong loader CPU rejection: %v\n%s", err, log))
	}
	c.Loader = oldLoader
	finalPayload, err := os.ReadFile(c.Payload)
	must(err)
	finalLoader, err := os.ReadFile(c.Loader)
	must(err)
	if sha256.Sum256(originalPayload) != sha256.Sum256(finalPayload) || sha256.Sum256(originalLoader) != sha256.Sum256(finalLoader) {
		panic("declared immutable inputs were modified")
	}
	fmt.Println("PASS: concurrent isolated prefixes; child execution; bounded cancellation and cleanup; independent server survival; exit 37; wrong-CPU rejection")
}
