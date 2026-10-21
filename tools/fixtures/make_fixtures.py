#!/usr/bin/env python3
"""Generate the fixture patches in Fixtures/patches from invented code.

Every byte here is original: an imaginary tea-kettle service ("kettle",
Go), an imaginary map renderer ("lantern", Rust plus tooling in five
other languages), and three small patches for parser edge cases. No
real project, review, or customer code is used (issue #13).

Real `git` makes the diffs, so the patches have the exact shape git
writes: extended headers, renames with a similarity index, binary
stubs, mode changes, a format-patch mail wrapper, and "\\ No newline".

    python3 tools/fixtures/make_fixtures.py      # writes Fixtures/patches/*.patch
    make bases                                   # then rebuild Fixtures/bases

Deterministic: fixed author, committer and dates, no randomness.
"""
import os
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "Fixtures", "patches")
ENV = dict(os.environ,
           GIT_AUTHOR_NAME="Fixture Author", GIT_AUTHOR_EMAIL="fixtures@example.invalid",
           GIT_COMMITTER_NAME="Fixture Author", GIT_COMMITTER_EMAIL="fixtures@example.invalid",
           GIT_AUTHOR_DATE="2026-10-21T12:00:00+00:00", GIT_COMMITTER_DATE="2026-10-21T12:00:00+00:00",
           GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null")


def git(repo, *args, out=False):
    r = subprocess.run(["git", "-C", repo, *args], env=ENV, check=True,
                       stdout=subprocess.PIPE if out else subprocess.DEVNULL)
    return r.stdout.decode() if out else None


def write(repo, path, text, mode=None):
    full = os.path.join(repo, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    data = text if isinstance(text, bytes) else text.encode()
    with open(full, "wb") as f:
        f.write(data)
    if mode:
        os.chmod(full, mode)


def save(path, text):
    """Write after the caller has read: `open(p, "w")` inside the same
    expression as `open(p).read()` would truncate the file first."""
    with open(path, "w") as f:
        f.write(text)


def remove(repo, path):
    git(repo, "rm", "-q", path)


def new_repo(files):
    repo = tempfile.mkdtemp(prefix="fixtures-")
    git(repo, "init", "-q", "-b", "base")
    git(repo, "config", "core.fileMode", "true")
    for path, text in files.items():
        write(repo, path, text)
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "base")
    return repo


def variant(repo, name, edit, mail=False, subject=None):
    git(repo, "checkout", "-q", "-B", name, "base")
    edit(repo)
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", subject or name)
    if mail:
        text = git(repo, "format-patch", "-1", "--stdout", "--no-signature", name, out=True)
    else:
        text = git(repo, "diff", "-M", "--no-color", "--no-ext-diff", "base", name, out=True)
    with open(os.path.join(OUT, name + ".patch"), "w") as f:
        f.write(text)
    print(f"{name}.patch: {text.count(chr(10) + 'diff --git') + text.startswith('diff --git')} files")


def insert_after(text, anchor, block):
    i = text.index(anchor) + len(anchor)
    return text[:i] + block + text[i:]


def replace_once(text, old, new):
    assert old in text, old
    return text.replace(old, new, 1)


# --------------------------------------------------------------------------
# kettle: an imaginary Go service that schedules brews. Four patches add
# "brew a batch" four different ways (the demo session and the review gates).

STEPS = ["Fill", "Heat", "Steep", "Pour", "Rinse", "Descale", "Cool", "Weigh", "Label", "Store",
         "Chill", "Stir", "Strain", "Vent", "Seal", "Check"]


def go_filler(prefix, n, recv="s *BrewTaskService"):
    out = []
    for i in range(n):
        step = STEPS[i % len(STEPS)]
        out.append(f"""
// {prefix}{step}{i} runs the {step.lower()} step for one brew and records
// how long it took, so the dashboard can show slow kettles.
func ({recv}) {prefix}{step}{i}(id int64) (time.Duration, error) {{
	start := time.Now()
	brew, err := s.repo.FindByID(id)
	if err != nil {{
		return 0, err
	}}
	brew.Step = "{step.lower()}"
	if err := s.repo.Save(brew); err != nil {{
		return 0, err
	}}
	return time.Since(start), nil
}}
""")
    return "".join(out)


def kettle_base():
    brew_task = """package service

import (
	"errors"
	"fmt"
	"time"

	"example.invalid/kettle/internal/core"
	"example.invalid/kettle/internal/pathutil"
	"example.invalid/kettle/internal/repo"
	"example.invalid/kettle/internal/tasklog"
)

// BrewTaskService is the business logic layer for brew tasks.
type BrewTaskService struct {
	repo  *repo.BrewRepository
	queue *core.TaskQueue
	logs  *tasklog.Manager
}

// NewBrewTaskService creates a BrewTaskService.
func NewBrewTaskService(repo *repo.BrewRepository, queue *core.TaskQueue, logs *tasklog.Manager) *BrewTaskService {
	return &BrewTaskService{repo: repo, queue: queue, logs: logs}
}

// AddBrewTaskInput holds the input for one brew.
type AddBrewTaskInput struct {
	Name   string `json:"name"`
	Blend  string `json:"blend"`
	Kettle string `json:"kettle"`
	Shelf  *string `json:"shelf"`
}

func normalizeInputShelf(ptr *string) (*string, error) {
	if ptr == nil {
		return nil, nil
	}
	norm, err := pathutil.NormalizeShelf(*ptr)
	if err != nil {
		return nil, err
	}
	return &norm, nil
}

// AddBrewTask adds a single brew task.
func (s *BrewTaskService) AddBrewTask(input AddBrewTaskInput) (*repo.Brew, error) {
	shelf, err := normalizeInputShelf(input.Shelf)
	if err != nil {
		return nil, err
	}
	name := input.Name
	if name == "" {
		name = fmt.Sprintf("untitled-%d", time.Now().Unix())
	}
	name = pathutil.SanitizeName(name)
	existing, err := s.repo.FindByName(name)
	if err != nil {
		return nil, err
	}
	if existing != nil {
		return nil, errors.New("a brew with that name already exists")
	}
	brew := &repo.Brew{Name: name, Blend: input.Blend, Kettle: input.Kettle, Shelf: shelf}
	if err := s.repo.Create(brew); err != nil {
		return nil, err
	}
	s.queue.Enqueue(brew.ID)
	return brew, nil
}
""" + go_filler("Run", 12) + """
// ListBrews returns every brew, newest first.
func (s *BrewTaskService) ListBrews() ([]*repo.Brew, error) {
	return s.repo.List()
}
"""
    files = {
        "go.mod": "module example.invalid/kettle\n\ngo 1.23\n",
        "cmd/server/main.go": """package main

import (
	"log"

	"example.invalid/kettle/internal/api"
	"example.invalid/kettle/internal/core"
	"example.invalid/kettle/internal/repo"
	"example.invalid/kettle/internal/service"
	"example.invalid/kettle/internal/tasklog"
)

func main() {
	brews := repo.NewBrewRepository("kettle.db")
	queue := core.NewTaskQueue(4)
	logs := tasklog.NewManager("logs")
	svc := service.NewBrewTaskService(brews, queue, logs)
	srv := api.NewServer(svc)
	log.Fatal(srv.Listen(":8080"))
}
""",
        "internal/service/brew_task.go": brew_task,
        "internal/service/helpers.go": """package service

import "strings"

// trimAll trims every string in place.
func trimAll(values []string) {
	for i := range values {
		values[i] = strings.TrimSpace(values[i])
	}
}

// RandomName returns a short name for an unnamed brew.
func RandomName() string {
	return "brew-" + strings.ToLower(time.Now().Format("150405"))
}
""",
        "internal/service/heater.go": """package service

// Heater turns a target temperature into a power level.
type Heater struct {
	Watts   int
	MaxTemp int
}

func (h Heater) Power(target int) int {
	if target >= h.MaxTemp {
		return h.Watts
	}
	return h.Watts * target / h.MaxTemp
}
""" + go_filler("Heater", 6, recv="s *Heater") ,
        "internal/service/heater_test.go": "package service\n\nimport \"testing\"\n" + "".join(
            f"""
func TestHeaterPowerCase{i}(t *testing.T) {{
	h := Heater{{Watts: {1000 + i * 10}, MaxTemp: 100}}
	if got := h.Power({i % 100}); got != {(1000 + i * 10) * (i % 100) // 100} {{
		t.Fatalf("case {i}: got %d", got)
	}}
}}
""" for i in range(300)),
        "internal/service/brew_task_test.go": """package service

import "testing"

func TestAddBrewTaskDefaultsTheName(t *testing.T) {
	s := newTestService(t)
	brew, err := s.AddBrewTask(AddBrewTaskInput{Blend: "sencha"})
	if err != nil {
		t.Fatal(err)
	}
	if brew.Name == "" {
		t.Fatal("empty name")
	}
}

func TestAddBrewTaskRejectsDuplicates(t *testing.T) {
	s := newTestService(t)
	if _, err := s.AddBrewTask(AddBrewTaskInput{Name: "a"}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.AddBrewTask(AddBrewTaskInput{Name: "a"}); err == nil {
		t.Fatal("expected an error")
	}
}
""",
        "internal/core/queue.go": """package core

import "sync"

// TaskQueue runs brews on a fixed number of kettles.
type TaskQueue struct {
	mu      sync.Mutex
	pending []int64
	slots   int
}

func NewTaskQueue(slots int) *TaskQueue { return &TaskQueue{slots: slots} }

// Enqueue adds one brew to the end of the queue.
func (q *TaskQueue) Enqueue(id int64) {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.pending = append(q.pending, id)
}

// Next removes and returns the first brew, or false when empty.
func (q *TaskQueue) Next() (int64, bool) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if len(q.pending) == 0 {
		return 0, false
	}
	id := q.pending[0]
	q.pending = q.pending[1:]
	return id, true
}
""",
        "internal/core/queue_test.go": """package core

import "testing"

func TestQueueIsFirstInFirstOut(t *testing.T) {
	q := NewTaskQueue(1)
	q.Enqueue(1)
	q.Enqueue(2)
	if id, _ := q.Next(); id != 1 {
		t.Fatalf("got %d", id)
	}
}
""",
        "internal/pathutil/pathutil.go": """package pathutil

import (
	"errors"
	"path/filepath"
	"strings"
)

// SanitizeName makes a brew name safe to use as a file name.
func SanitizeName(name string) string {
	name = strings.TrimSpace(name)
	name = strings.ReplaceAll(name, "/", "-")
	return strings.ReplaceAll(name, "\\\\", "-")
}

// NormalizeShelf cleans a shelf path and keeps it relative.
func NormalizeShelf(p string) (string, error) {
	clean := filepath.Clean(p)
	if filepath.IsAbs(clean) || strings.HasPrefix(clean, "..") {
		return "", errors.New("shelf must stay inside the pantry")
	}
	return clean, nil
}
""",
        "internal/pathutil/pathutil_test.go": """package pathutil

import "testing"

func TestSanitizeNameReplacesSlashes(t *testing.T) {
	if got := SanitizeName("a/b"); got != "a-b" {
		t.Fatalf("got %q", got)
	}
}

func TestNormalizeShelfRejectsEscapes(t *testing.T) {
	if _, err := NormalizeShelf("../x"); err == nil {
		t.Fatal("expected an error")
	}
}
""",
        "internal/api/server.go": """package api

import (
	"net/http"

	"example.invalid/kettle/internal/api/handler"
	"example.invalid/kettle/internal/service"
)

type Server struct {
	mux *http.ServeMux
}

func NewServer(svc *service.BrewTaskService) *Server {
	mux := http.NewServeMux()
	h := handler.NewBrewHandler(svc)
	mux.HandleFunc("POST /brews", h.Add)
	mux.HandleFunc("GET /brews", h.List)
	return &Server{mux: mux}
}

func (s *Server) Listen(addr string) error { return http.ListenAndServe(addr, s.mux) }
""",
        "internal/api/handler/brew.go": """package handler

import (
	"encoding/json"
	"net/http"

	"example.invalid/kettle/internal/api/dto"
	"example.invalid/kettle/internal/service"
)

type BrewHandler struct {
	svc *service.BrewTaskService
}

func NewBrewHandler(svc *service.BrewTaskService) *BrewHandler { return &BrewHandler{svc: svc} }

// Add handles POST /brews.
func (h *BrewHandler) Add(w http.ResponseWriter, r *http.Request) {
	var req dto.AddBrewRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	brew, err := h.svc.AddBrewTask(req.Input())
	if err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	json.NewEncoder(w).Encode(brew)
}

// List handles GET /brews.
func (h *BrewHandler) List(w http.ResponseWriter, r *http.Request) {
	brews, err := h.svc.ListBrews()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(brews)
}
""",
        "internal/api/handler/brew_test.go": """package handler

import "testing"

func TestAddRejectsBadJSON(t *testing.T) {
	rec := doRequest(t, "POST", "/brews", "{")
	if rec.Code != 400 {
		t.Fatalf("got %d", rec.Code)
	}
}
""",
        "internal/api/dto/brew.go": """package dto

import "example.invalid/kettle/internal/service"

// AddBrewRequest is the JSON body of POST /brews.
type AddBrewRequest struct {
	Name   string  `json:"name"`
	Blend  string  `json:"blend"`
	Kettle string  `json:"kettle"`
	Shelf  *string `json:"shelf"`
}

func (r AddBrewRequest) Input() service.AddBrewTaskInput {
	return service.AddBrewTaskInput{Name: r.Name, Blend: r.Blend, Kettle: r.Kettle, Shelf: r.Shelf}
}
""",
    }
    return files


def kettle_edit(v):
    """Four ways to add "brew a batch". v is 1..4."""
    def edit(repo):
        p = os.path.join(repo, "internal/service/brew_task.go")
        text = open(p).read()
        if v == 1:
            text = replace_once(text, "\tlogs  *tasklog.Manager\n}", "\tlogs  *tasklog.Manager\n\t// pantryRoot resolves relative shelves.\n\tpantryRoot func() string\n}")
            block = """
// AddBrewTasks adds several brews at once. Every name is checked before
// any brew is created, so a bad batch leaves nothing half done.
func (s *BrewTaskService) AddBrewTasks(inputs []AddBrewTaskInput) ([]*repo.Brew, error) {
	reserved := reserveNames(inputs)
	for i, input := range inputs {
		if _, err := normalizeInputShelf(input.Shelf); err != nil {
			return nil, fmt.Errorf("brew %d: %w", i, err)
		}
	}
	brews := make([]*repo.Brew, 0, len(inputs))
	for i, input := range inputs {
		input.Name = reserved[i]
		brew, err := s.AddBrewTask(input)
		if err != nil {
			return nil, err
		}
		brews = append(brews, brew)
	}
	return brews, nil
}

// reserveNames gives every unnamed brew in a batch a distinct name.
func reserveNames(inputs []AddBrewTaskInput) []string {
	names := make([]string, len(inputs))
	used := map[string]bool{}
	for i, input := range inputs {
		name := input.Name
		if name == "" {
			name = RandomName()
		}
		for used[name] {
			name = name + "-" + RandomName()
		}
		used[name] = true
		names[i] = name
	}
	return names
}
"""
        elif v == 2:
            block = """
// AddBrewTasks adds several brews, one after another.
func (s *BrewTaskService) AddBrewTasks(inputs []AddBrewTaskInput) ([]*repo.Brew, error) {
	var brews []*repo.Brew
	for _, input := range inputs {
		brew, err := s.AddBrewTask(input)
		if err != nil {
			return brews, err
		}
		brews = append(brews, brew)
	}
	return brews, nil
}
"""
        elif v == 3:
            text = replace_once(text, "\tname = pathutil.SanitizeName(name)\n", "\tname = pathutil.SanitizeName(name)\n\tname, err = s.availableName(name, 0)\n\tif err != nil {\n\t\treturn nil, err\n\t}\n")
            block = """
// AddBrewTasks adds several brews at once.
func (s *BrewTaskService) AddBrewTasks(inputs []AddBrewTaskInput) ([]*repo.Brew, error) {
	brews := make([]*repo.Brew, 0, len(inputs))
	for _, input := range inputs {
		if err := s.validateInputShelf(input.Shelf); err != nil {
			return nil, err
		}
		brew, err := s.AddBrewTask(input)
		if err != nil {
			return nil, err
		}
		brews = append(brews, brew)
	}
	return brews, nil
}

// availableName appends a counter until the name is free.
func (s *BrewTaskService) availableName(name string, n int) (string, error) {
	candidate := name
	if n > 0 {
		candidate = fmt.Sprintf("%s (%d)", name, n)
	}
	existing, err := s.repo.FindByName(candidate)
	if err != nil {
		return "", err
	}
	if existing == nil {
		return candidate, nil
	}
	return s.availableName(name, n+1)
}

func (s *BrewTaskService) validateInputShelf(shelf *string) error {
	_, err := normalizeInputShelf(shelf)
	return err
}
"""
        else:
            block = """
// AddBrewTasks adds several brews at once.
// It validates every input first.
// Then it creates every brew.
// Then it enqueues every brew.
func (s *BrewTaskService) AddBrewTasks(inputs []AddBrewTaskInput) ([]*repo.Brew, error) {
	if inputs == nil {
		return nil, nil
	}
	if len(inputs) == 0 {
		return []*repo.Brew{}, nil
	}
	// Validate every input first.
	for _, input := range inputs {
		if input.Shelf != nil {
			if _, err := pathutil.NormalizeShelf(*input.Shelf); err != nil {
				return nil, err
			}
		}
	}
	// Create every brew.
	brews := make([]*repo.Brew, 0, len(inputs))
	for _, input := range inputs {
		name := input.Name
		if name == "" {
			name = fmt.Sprintf("untitled-%d", time.Now().Unix())
		}
		name = pathutil.SanitizeName(name)
		brew := &repo.Brew{Name: name, Blend: input.Blend, Kettle: input.Kettle}
		if err := s.repo.Create(brew); err != nil {
			return nil, err
		}
		brews = append(brews, brew)
	}
	// Enqueue every brew.
	for _, brew := range brews {
		s.queue.Enqueue(brew.ID)
	}
	return brews, nil
}
"""
        text = insert_after(text, "\ts.queue.Enqueue(brew.ID)\n\treturn brew, nil\n}\n", block)
        # Each version also edits a few of the step functions differently.
        for i in range(12):
            if (i + v) % 4 == 0:
                step = STEPS[i % len(STEPS)].lower()
                text = replace_once(text, f'\tbrew.Step = "{step}"\n', f'\tbrew.Step = "{step}"\n\tbrew.UpdatedAt = time.Now()\n')
        save(p, text)

        # Queue: EnqueueMany, four spellings.
        p = os.path.join(repo, "internal/core/queue.go")
        q = open(p).read()
        many = {
            1: "\n// EnqueueMany adds brews in order under one lock.\nfunc (q *TaskQueue) EnqueueMany(ids []int64) {\n\tq.mu.Lock()\n\tdefer q.mu.Unlock()\n\tq.pending = append(q.pending, ids...)\n}\n",
            2: "\n// EnqueueMany adds brews in order.\nfunc (q *TaskQueue) EnqueueMany(ids []int64) {\n\tfor _, id := range ids {\n\t\tq.Enqueue(id)\n\t}\n}\n",
            3: "\n// EnqueueMany adds brews in order under one lock.\nfunc (q *TaskQueue) EnqueueMany(ids []int64) {\n\tq.mu.Lock()\n\tq.pending = append(q.pending, ids...)\n\tq.mu.Unlock()\n}\n",
            4: "\n// EnqueueMany adds brews in order.\n// It takes the lock once.\nfunc (q *TaskQueue) EnqueueMany(ids []int64) {\n\tif len(ids) == 0 {\n\t\treturn\n\t}\n\tq.mu.Lock()\n\tdefer q.mu.Unlock()\n\tfor _, id := range ids {\n\t\tq.pending = append(q.pending, id)\n\t}\n}\n",
        }[v]
        save(p, insert_after(q, "\tq.pending = append(q.pending, id)\n}\n", many))

        # Handler, DTO and route for POST /brews/batch.
        p = os.path.join(repo, "internal/api/handler/brew.go")
        h = open(p).read()
        status = {1: "StatusUnprocessableEntity", 2: "StatusConflict", 3: "StatusBadRequest", 4: "StatusConflict"}[v]
        h = insert_after(h, "\tjson.NewEncoder(w).Encode(brew)\n}\n", f"""
// AddBatch handles POST /brews/batch.
func (h *BrewHandler) AddBatch(w http.ResponseWriter, r *http.Request) {{
	var req dto.AddBrewBatchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {{
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}}
	brews, err := h.svc.AddBrewTasks(req.Inputs())
	if err != nil {{
		http.Error(w, err.Error(), http.{status})
		return
	}}
	json.NewEncoder(w).Encode(brews)
}}
""")
        save(p, h)
        p = os.path.join(repo, "internal/api/dto/brew.go")
        d = open(p).read()
        d += """
// AddBrewBatchRequest is the JSON body of POST /brews/batch.
type AddBrewBatchRequest struct {
	Brews []AddBrewRequest `json:"brews"`
}

func (r AddBrewBatchRequest) Inputs() []service.AddBrewTaskInput {
	out := make([]service.AddBrewTaskInput, len(r.Brews))
	for i, b := range r.Brews {
		out[i] = b.Input()
	}
	return out
}
"""
        if v == 4:
            d += "\n// MaxBatch is the largest batch a request may carry.\nconst MaxBatch = 64\n"
        save(p, d)
        p = os.path.join(repo, "internal/api/server.go")
        save(p, replace_once(open(p).read(), '\tmux.HandleFunc("GET /brews", h.List)\n',
                                        '\tmux.HandleFunc("GET /brews", h.List)\n\tmux.HandleFunc("POST /brews/batch", h.AddBatch)\n'))

        # Tests: each version tests the batch its own way.
        p = os.path.join(repo, "internal/service/brew_task_test.go")
        t = open(p).read()
        t += {
            1: "\nfunc TestAddBrewTasksGivesUnnamedBrewsDistinctNames(t *testing.T) {\n\ts := newTestService(t)\n\tbrews, err := s.AddBrewTasks([]AddBrewTaskInput{{}, {}})\n\tif err != nil {\n\t\tt.Fatal(err)\n\t}\n\tif brews[0].Name == brews[1].Name {\n\t\tt.Fatal(\"names collide\")\n\t}\n}\n\nfunc TestAddBrewTasksLeavesNothingOnABadShelf(t *testing.T) {\n\ts := newTestService(t)\n\tbad := \"../out\"\n\tif _, err := s.AddBrewTasks([]AddBrewTaskInput{{Name: \"a\"}, {Shelf: &bad}}); err == nil {\n\t\tt.Fatal(\"expected an error\")\n\t}\n\tif brews, _ := s.ListBrews(); len(brews) != 0 {\n\t\tt.Fatal(\"half a batch was created\")\n\t}\n}\n",
            2: "\nfunc TestAddBrewTasksAddsEach(t *testing.T) {\n\ts := newTestService(t)\n\tbrews, err := s.AddBrewTasks([]AddBrewTaskInput{{Name: \"a\"}, {Name: \"b\"}})\n\tif err != nil || len(brews) != 2 {\n\t\tt.Fatal(err)\n\t}\n}\n",
            3: "\nfunc TestAvailableNameCounts(t *testing.T) {\n\ts := newTestService(t)\n\ts.AddBrewTask(AddBrewTaskInput{Name: \"a\"})\n\tname, _ := s.availableName(\"a\", 0)\n\tif name != \"a (1)\" {\n\t\tt.Fatalf(\"got %q\", name)\n\t}\n}\n",
            4: "\nfunc TestAddBrewTasksNil(t *testing.T) {\n\ts := newTestService(t)\n\tbrews, err := s.AddBrewTasks(nil)\n\tif err != nil || brews != nil {\n\t\tt.Fatal(\"expected nil\")\n\t}\n}\n\nfunc TestAddBrewTasksEmpty(t *testing.T) {\n\ts := newTestService(t)\n\tbrews, err := s.AddBrewTasks([]AddBrewTaskInput{})\n\tif err != nil || len(brews) != 0 {\n\t\tt.Fatal(\"expected empty\")\n\t}\n}\n",
        }[v]
        save(p, t)
        p = os.path.join(repo, "internal/core/queue_test.go")
        save(p, open(p).read() + f"\nfunc TestEnqueueManyKeepsOrder{v}(t *testing.T) {{\n\tq := NewTaskQueue(1)\n\tq.EnqueueMany([]int64{{1, 2, 3}})\n\tif id, _ := q.Next(); id != 1 {{\n\t\tt.Fatalf(\"got %d\", id)\n\t}}\n}}\n")
        p = os.path.join(repo, "internal/api/handler/brew_test.go")
        save(p, open(p).read() + f"\nfunc TestAddBatchRejectsBadJSON{v}(t *testing.T) {{\n\trec := doRequest(t, \"POST\", \"/brews/batch\", \"[\")\n\tif rec.Code != 400 {{\n\t\tt.Fatalf(\"got %d\", rec.Code)\n\t}}\n}}\n")

        if v in (1, 3, 4):
            p = os.path.join(repo, "internal/pathutil/pathutil.go")
            pu = open(p).read()
            if v == 1:
                pu = replace_once(pu, '\treturn strings.ReplaceAll(name, "\\\\", "-")\n', '\tname = strings.ReplaceAll(name, "\\\\", "-")\n\treturn strings.Trim(name, ".")\n')
            elif v == 3:
                pu += "\n// SanitizeBasename keeps only the last path element of a name.\nfunc SanitizeBasename(name string) string {\n\treturn SanitizeName(filepath.Base(name))\n}\n"
            else:
                pu = replace_once(pu, "\tname = strings.TrimSpace(name)\n", "\tif name == \"\" {\n\t\treturn name\n\t}\n\tname = strings.TrimSpace(name)\n")
            save(p, pu)
            p = os.path.join(repo, "internal/pathutil/pathutil_test.go")
            save(p, open(p).read() + f"\nfunc TestSanitizeNameCase{v}(t *testing.T) {{\n\tif got := SanitizeName(\" x \"); got != \"x\" {{\n\t\tt.Fatalf(\"got %q\", got)\n\t}}\n}}\n")

        if v == 2:
            # The search gate: one patch, and only this one, uses tempFor(k)
            # more than sixty times.
            p = os.path.join(repo, "internal/service/heater.go")
            save(p, open(p).read() + "\n// tempFor returns the brewing temperature for a kettle's blend.\nfunc tempFor(k *Kettle) int {\n\treturn blendTemps[k.Blend]\n}\n")
            rows = "".join(f"\t{{\"case {i}\", func(k *Kettle) int {{ return tempFor(k) + {i} }}}},\n" for i in range(64))
            write(repo, "internal/service/temperature_test.go",
                  "package service\n\nimport \"testing\"\n\nvar tempCases = []struct {\n\tname string\n\tfn   func(*Kettle) int\n}{\n" + rows +
                  "}\n\nfunc TestTempCases(t *testing.T) {\n\tfor _, c := range tempCases {\n\t\tif c.fn(&Kettle{Blend: \"sencha\"}) < 0 {\n\t\t\tt.Fatal(c.name)\n\t\t}\n\t}\n}\n")
        if v in (1, 4):
            p = os.path.join(repo, "cmd/server/main.go")
            save(p, replace_once(open(p).read(), "\tqueue := core.NewTaskQueue(4)\n", "\tqueue := core.NewTaskQueue(8)\n"))
        if v in (3, 4):
            p = os.path.join(repo, "internal/service/helpers.go")
            save(p, open(p).read() + "\n// uniqueNames reports whether every name in a batch is distinct.\nfunc uniqueNames(names []string) bool {\n\tseen := map[string]bool{}\n\tfor _, n := range names {\n\t\tif seen[n] {\n\t\t\treturn false\n\t\t}\n\t\tseen[n] = true\n\t}\n\treturn true\n}\n")
        # A change deep in the long test file, for scroll lock across columns.
        p = os.path.join(repo, "internal/service/heater_test.go")
        ht = open(p).read()
        case = 150 + v * 20
        ht = replace_once(ht, f'\t\tt.Fatalf("case {case}: got %d", got)\n', f'\t\tt.Fatalf("case {case} (variant {v}): got %d, want a lower power", got)\n')
        save(p, ht)
    return edit


# --------------------------------------------------------------------------
# lantern: an imaginary map renderer. Three patches add "glow" layers;
# only the third parses a glow- prefix (the absent-region gate), and all
# three reshape fn glow_schema (the identifier gate).

def rust_filler(n):
    names = ["tile", "layer", "palette", "legend", "contour", "shade", "label", "grid", "scale", "marker",
             "border", "road", "river", "coast", "peak", "valley", "forest", "town", "bridge", "ferry"]
    out = []
    for i in range(n):
        nm = names[i % len(names)]
        out.append(f"""
/// Draws the {nm} pass for one tile and returns how many features it placed.
fn draw_{nm}_{i}(tile: &Tile, out: &mut Canvas) -> usize {{
    let mut placed = 0;
    for feature in tile.features.iter().filter(|f| f.kind == Kind::{nm.capitalize()}) {{
        out.stroke(&feature.path, Style::for_kind(Kind::{nm.capitalize()}));
        placed += 1;
    }}
    placed
}}
""")
    return "".join(out)


def lantern_base():
    main = """use std::collections::HashMap;
use std::fs::File;
use std::path::Path;
use std::sync::Arc;

use glowmap::canvas::{Canvas, Style};
use glowmap::schema::{DataType, Field, Schema};
use glowmap::tile::{Kind, Tile};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum OutputMode {
    Stream,
    File,
}

fn canonical_schema() -> Arc<Schema> {
    Arc::new(Schema::new(vec![
        Field::new("id", DataType::Int32, false),
        Field::new("name", DataType::Utf8, true),
    ]))
}

fn glow_schema(level_type: DataType) -> Arc<Schema> {
    Arc::new(Schema::new(vec![
        Field::new("id", DataType::Int32, false),
        Field::new("level", level_type, false),
        Field::new("tint", DataType::Utf8, true),
    ]))
}
""" + rust_filler(40) + """
fn run_case(case: &str, mode: OutputMode, out: &Path) -> std::io::Result<()> {
    let schema = match case {
        "basic" => canonical_schema(),
        "glow-i16" => glow_schema(DataType::Int16),
        "glow-i32" => glow_schema(DataType::Int32),
        "glow-i64" => glow_schema(DataType::Int64),
        other => panic!("unknown case {other}"),
    };
    let file = File::create(out)?;
    write_output(file, &schema, mode)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut case = args.get(1).cloned().unwrap_or_else(|| "basic".to_string());
    let mode = if args.iter().any(|a| a == "--file") { OutputMode::File } else { OutputMode::Stream };
    if case == "glow" && mode == OutputMode::Stream {
        case = "glow-i32".to_string();
    }
    let out = Path::new(args.get(2).map(String::as_str).unwrap_or("out.glow"));
    run_case(&case, mode, out).expect("write failed");
}
"""
    return {
        "crates/glowmap/src/main.rs": main,
        "crates/glowmap/Cargo.toml": "[package]\nname = \"glowmap\"\nversion = \"0.3.0\"\nedition = \"2021\"\n\n[dependencies]\nserde = \"1.0\"\n",
        ".github/workflows/ci.yml": "name: ci\non: [push, pull_request]\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n      - name: build\n        run: cargo build --release\n      - name: test\n        run: cargo test\n",
        "README.md": "# Lantern\n\nRenders map tiles with soft glow layers.\n\n## Build\n\n```\ncargo build --release\n```\n\n## Cases\n\n- `basic`: ids and names only.\n- `glow-i16`, `glow-i32`, `glow-i64`: a glow level per feature.\n",
        "docs/guide.md": "# Guide\n\nEach case writes one stream. Use `--file` for the file container.\n\n| case | columns |\n|---|---|\n| basic | id, name |\n| glow-i32 | id, level, tint |\n",
        "tools/check_glow.sh": "#!/bin/sh\nset -eu\n# Write every case and check it with the Python validator.\nfor case in basic glow-i16 glow-i32 glow-i64; do\n  cargo run -q -- \"$case\" \"out/$case.glow\"\n  python3 tools/py/glow_validate.py \"out/$case.glow\"\ndone\necho \"all cases ok\"\n",
        "tools/glow_fixture_writer.zig": "const std = @import(\"std\");\n\npub fn main() !void {\n    const stdout = std.io.getStdOut().writer();\n    try stdout.print(\"{s}\\n\", .{\"basic\"});\n}\n",
        "tools/glow_fixture_check.zig": "const std = @import(\"std\");\n\ntest \"basic case has two columns\" {\n    try std.testing.expectEqual(@as(u32, 2), 2);\n}\n",
        "tools/cpp/glow.cpp": "#include <iostream>\n#include <string>\n\n// Prints the column names of one case.\nint main(int argc, char** argv) {\n    std::string c = argc > 1 ? argv[1] : \"basic\";\n    std::cout << \"id,name\" << std::endl;\n    return 0;\n}\n",
        "tools/py/glow_generate.py": "\"\"\"Write a reference stream for every case.\"\"\"\nimport sys\n\nCASES = [\"basic\", \"glow-i16\", \"glow-i32\", \"glow-i64\"]\n\n\ndef generate(case: str) -> list[dict]:\n    if case == \"basic\":\n        return [{\"id\": 1, \"name\": \"a\"}]\n    return [{\"id\": 1, \"level\": 3, \"tint\": \"amber\"}]\n\n\nif __name__ == \"__main__\":\n    for case in CASES:\n        print(case, generate(case))\n",
        "tools/py/glow_validate.py": "\"\"\"Check one written stream against its case.\"\"\"\nimport sys\n\n\ndef validate(path: str) -> bool:\n    with open(path, \"rb\") as f:\n        head = f.read(4)\n    return head == b\"GLOW\"\n\n\nif __name__ == \"__main__\":\n    sys.exit(0 if validate(sys.argv[1]) else 1)\n",
    }


def lantern_edit(v):
    def edit(repo):
        p = os.path.join(repo, "crates/glowmap/src/main.rs")
        m = open(p).read()
        old_schema = """fn glow_schema(level_type: DataType) -> Arc<Schema> {
    Arc::new(Schema::new(vec![
        Field::new("id", DataType::Int32, false),
        Field::new("level", level_type, false),
        Field::new("tint", DataType::Utf8, true),
    ]))
}
"""
        new_schema = {
            1: """fn glow_schema(level_type: DataType) -> Arc<Schema> {
    Arc::new(Schema::new(vec![
        Field::new("id", DataType::Int32, false),
        Field::new("level", level_type, false),
        Field::new("tint", DataType::Utf8, true),
        Field::new("radius", DataType::Float32, true),
    ]))
}
""",
            2: """fn glow_schema(level: DataType) -> Arc<Schema> {
    let fields = vec![
        Field::new("id", DataType::Int32, false),
        Field::new("level", level, false),
        Field::new("tint", DataType::Utf8, true),
    ];
    Arc::new(Schema::new(fields))
}
""",
            3: """fn glow_schema(level_type: DataType) -> Arc<Schema> {
    Arc::new(Schema::new(vec![
        Field::new("id", DataType::Int32, false),
        Field::new("level", level_type, true),
        Field::new("tint", DataType::Utf8, true),
    ]))
}
""",
        }[v]
        m = replace_once(m, old_schema, new_schema)
        # A change near the end of the file in every version, so the
        # absent block in the other two has a nearby hunk to point at.
        if v == 1:
            m = replace_once(m, '        "glow-i64" => glow_schema(DataType::Int64),\n',
                             '        "glow-i64" => glow_schema(DataType::Int64),\n        "glow-f32" => glow_schema(DataType::Float32),\n')
        elif v == 2:
            m = replace_once(m, "    let file = File::create(out)?;\n", "    let file = File::create(out).map_err(|e| {\n        eprintln!(\"cannot create {}: {e}\", out.display());\n        e\n    })?;\n")
        else:
            m = replace_once(m, '    if case == "glow" && mode == OutputMode::Stream {\n        case = "glow-i32".to_string();\n    }\n',
                             '    if case == "glow" && mode == OutputMode::Stream {\n        case = "glow-i32".to_string();\n    }\n    if let Some(rest) = case.strip_prefix("glow-") {\n        case = format!("glow-{}", rest.to_lowercase());\n    }\n')
        # Version two also renames a run of helpers (a restructure).
        if v == 2:
            for name in ["tile", "layer", "palette"]:
                m = m.replace(f"fn draw_{name}_", f"fn paint_{name}_")
        save(p, m)

        p = os.path.join(repo, ".github/workflows/ci.yml")
        ci = open(p).read()
        extra = {1: "      - name: fixtures\n        run: sh tools/check_glow.sh\n",
                 2: "      - name: lint\n        run: cargo clippy -- -D warnings\n",
                 3: "      - name: fixtures\n        run: sh tools/check_glow.sh\n      - name: zig\n        run: zig test tools/glow_fixture_check.zig\n"}[v]
        save(p, ci + extra)
        p = os.path.join(repo, "README.md")
        save(p, open(p).read() + {1: "- `glow-f32`: a float glow level.\n", 2: "\nErrors name the file that could not be created.\n", 3: "\nCase names are matched without regard to case after `glow-`.\n"}[v])
        p = os.path.join(repo, "tools/py/glow_generate.py")
        g = open(p).read()
        g = replace_once(g, 'CASES = ["basic", "glow-i16", "glow-i32", "glow-i64"]', {1: 'CASES = ["basic", "glow-i16", "glow-i32", "glow-i64", "glow-f32"]', 2: 'CASES = ["basic", "glow-i16", "glow-i32", "glow-i64"]  # keep in step with main.rs', 3: 'CASES = ["basic", "glow-i16", "glow-i32", "glow-i64", "GLOW-I32"]'}[v])
        save(p, g)
        p = os.path.join(repo, "tools/py/glow_validate.py")
        save(p, replace_once(open(p).read(), '    return head == b"GLOW"\n', {1: '    return head in (b"GLOW", b"GLW2")\n', 2: '    if not head:\n        return False\n    return head == b"GLOW"\n', 3: '    return head.upper() == b"GLOW"\n'}[v]))
        p = os.path.join(repo, "tools/check_glow.sh")
        save(p, replace_once(open(p).read(), "for case in basic glow-i16 glow-i32 glow-i64; do\n", {1: "for case in basic glow-i16 glow-i32 glow-i64 glow-f32; do\n", 2: "mkdir -p out\nfor case in basic glow-i16 glow-i32 glow-i64; do\n", 3: "for case in basic glow-i16 glow-i32 glow-i64 GLOW-I32; do\n"}[v]))
        p = os.path.join(repo, "tools/glow_fixture_writer.zig")
        save(p, replace_once(open(p).read(), '    try stdout.print("{s}\\n", .{"basic"});\n', {1: '    for ([_][]const u8{ "basic", "glow-f32" }) |c| try stdout.print("{s}\\n", .{c});\n', 2: '    try stdout.print("{s}\\n", .{"basic"});\n    try stdout.print("{s}\\n", .{"glow-i32"});\n', 3: '    for ([_][]const u8{ "basic", "GLOW-I32" }) |c| try stdout.print("{s}\\n", .{c});\n'}[v]))
        if v != 2:
            p = os.path.join(repo, "tools/cpp/glow.cpp")
            save(p, replace_once(open(p).read(), '    std::cout << "id,name" << std::endl;\n', '    std::cout << (c == "basic" ? "id,name" : "id,level,tint") << std::endl;\n'))
        if v == 1:
            write(repo, "tools/py/test_glow.py", "from glow_generate import generate\n\n\ndef test_basic_has_a_name():\n    assert generate(\"basic\")[0][\"name\"] == \"a\"\n\n\ndef test_glow_cases_have_a_level():\n    for case in [\"glow-i16\", \"glow-i32\", \"glow-f32\"]:\n        assert \"level\" in generate(case)[0]\n")
        if v == 3:
            p = os.path.join(repo, "docs/guide.md")
            save(p, open(p).read() + "| GLOW-I32 | id, level, tint (same as glow-i32) |\n")
    return edit


# --------------------------------------------------------------------------
# Three small patches for parser and apply edge cases.

def scaffold():
    repo = new_repo({
        "Cargo.toml": "[workspace]\nmembers = [\"crates/*\"]\nresolver = \"2\"\n",
        "styles/site.css": "body {\n  margin: 0;\n  font-family: system-ui;\n  color: #222;\n}\n\n.card {\n  padding: 12px;\n  border-radius: 6px;\n}\n",
        "tools/run.sh": "#!/bin/sh\nexec cargo run -- \"$@\"\n",
        "docs/old-notes.md": "# Old notes\n\nThese notes describe the first prototype.\nThey are kept for history only.\n",
    })

    def edit(r):
        write(r, "AGENTS.md", "# Agents\n\nRun `cargo test` before every commit.\nKeep crates free of network access.\n")
        write(r, "CLAUDE.md", "See AGENTS.md.\n")
        p = os.path.join(r, "Cargo.toml")
        save(p, open(p).read() + "\n[workspace.package]\nedition = \"2021\"\nlicense = \"MIT\"\n")
        p = os.path.join(r, "styles/site.css")
        save(p, replace_once(open(p).read(), "  padding: 12px;\n", "  padding: 16px;\n  box-shadow: 0 1px 3px #0003;\n"))
        write(r, "assets/logo.png", bytes([137, 80, 78, 71, 13, 10, 26, 10] + [i * 7 % 256 for i in range(300)]))
        os.chmod(os.path.join(r, "tools/run.sh"), 0o755)
        remove(r, "docs/old-notes.md")
    variant(repo, "scaffold", edit)
    shutil.rmtree(repo)


def rename():
    ledger_test = "\"\"\"Tests for the ledger.\"\"\"\nimport pytest\n\nfrom ledger.core import Ledger\n\n\n" + "".join(
        f"def test_entry_{i}():\n    ledger = Ledger()\n    ledger.add({i}, \"item {i}\")\n    assert ledger.total() == {i}\n\n\n" for i in range(12))
    repo = new_repo({
        "tests/billing/test_ledger.py": ledger_test,
        "ledger/core.py": "\"\"\"A tiny ledger.\"\"\"\n\n\nclass Ledger:\n    def __init__(self):\n        self.entries = []\n\n    def add(self, amount, memo):\n        self.entries.append((amount, memo))\n\n    def total(self):\n        return sum(a for a, _ in self.entries)\n",
        "ledger/legacy.py": "\"\"\"Old import path, kept for one release.\"\"\"\nfrom ledger.core import Ledger  # noqa: F401\n",
        "pyproject.toml": "[project]\nname = \"ledger\"\nversion = \"0.1.0\"\n\n[tool.pytest.ini_options]\ntestpaths = [\"tests/billing\"]\n",
    })

    def edit(r):
        git(r, "mv", "tests/billing/test_ledger.py", "tests/test_ledger.py")
        p = os.path.join(r, "tests/test_ledger.py")
        t = open(p).read()
        t = replace_once(t, "def test_entry_0():\n    ledger = Ledger()\n", "def test_entry_0():\n    ledger = Ledger()\n    assert ledger.total() == 0\n")
        t = replace_once(t, "import pytest\n", "import pytest  # noqa: F401\n")
        save(p, t)
        p = os.path.join(r, "ledger/core.py")
        save(p, open(p).read() + "\n    def memos(self):\n        return [m for _, m in self.entries]\n")
        p = os.path.join(r, "pyproject.toml")
        save(p, replace_once(open(p).read(), 'testpaths = ["tests/billing"]', 'testpaths = ["tests"]'))
        remove(r, "ledger/legacy.py")
    variant(repo, "rename", edit)
    shutil.rmtree(repo)


def mail():
    repo = new_repo({
        "src/App.vue": "<template>\n  <main class=\"app\">\n    <h1>{{ title }}</h1>\n  </main>\n</template>\n\n<script setup lang=\"ts\">\nconst title = 'Lantern'\n</script>\n",
        "src/app.ts": "export interface Tile {\n  x: number\n  y: number\n  zoom: number\n}\n\nexport function key(t: Tile): string {\n  return `${t.zoom}/${t.x}/${t.y}`\n}\n",
        "src/style.css": ".app {\n  max-width: 960px;\n  margin: 0 auto;\n}\n",
        "config/site.yml": "site:\n  title: Lantern\n  base: /\n  tiles:\n    cache: 64\n",
        "notes.txt": "first line\nsecond line\nlast line without a newline",
        "README.md": "# Lantern web\n\nA viewer for lantern tiles.\n",
    })

    def edit(r):
        p = os.path.join(r, "src/App.vue")
        save(p, replace_once(open(p).read(), "    <h1>{{ title }}</h1>\n", "    <h1>{{ title }}</h1>\n    <p class=\"zoom\">zoom {{ zoom }}</p>\n").replace("const title = 'Lantern'\n", "const title = 'Lantern'\nconst zoom = 3\n"))
        p = os.path.join(r, "src/app.ts")
        save(p, replace_once(open(p).read(), "export function key(t: Tile): string {\n", "export const MAX_ZOOM = 18\n\nexport function key(t: Tile): string {\n  if (t.zoom > MAX_ZOOM) throw new Error('zoom too deep')\n"))
        p = os.path.join(r, "src/style.css")
        save(p, open(p).read() + "\n.zoom {\n  color: #666;\n}\n")
        p = os.path.join(r, "config/site.yml")
        save(p, replace_once(open(p).read(), "    cache: 64\n", "    cache: 128\n    max_zoom: 18\n"))
        open(os.path.join(r, "notes.txt"), "w").write("first line\nsecond line, edited\nlast line still without a newline")
        p = os.path.join(r, "README.md")
        save(p, open(p).read() + "\nTiles deeper than zoom 18 are refused.\n")
    variant(repo, "mail", edit, mail=True, subject="Cap tile zoom at 18\n\nDeeper tiles are never rendered; refuse them early.")
    shutil.rmtree(repo)


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".patch"):
            os.remove(os.path.join(OUT, f))
    repo = new_repo(kettle_base())
    for v in range(1, 5):
        variant(repo, f"kettle-{v}", kettle_edit(v))
    shutil.rmtree(repo)
    repo = new_repo(lantern_base())
    for v in range(1, 4):
        variant(repo, f"lantern-{v}", lantern_edit(v))
    shutil.rmtree(repo)
    scaffold()
    rename()
    mail()


if __name__ == "__main__":
    sys.exit(main())
