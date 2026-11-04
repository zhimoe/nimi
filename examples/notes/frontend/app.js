(() => {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const els = {
    newNote: $("new-note"),
    emptyNew: $("empty-new"),
    search: $("search"),
    noteList: $("note-list"),
    noteCount: $("note-count"),
    import: $("import"),
    title: $("title"),
    editor: $("editor"),
    preview: $("preview"),
    status: $("status"),
    export: $("export"),
    delete: $("delete"),
    editorWrap: $("editor-wrap"),
    empty: $("empty"),
    wordCount: $("word-count"),
    updated: $("updated"),
    confirm: $("confirm"),
    confirmTitle: $("confirm-title"),
    confirmCancel: $("confirm-cancel"),
    confirmOk: $("confirm-ok"),
  };

  const state = {
    notes: [],
    selectedId: null,
    query: "",
    saveTimer: null,
    dirtyNoteId: null,
    saveChain: Promise.resolve(),
    confirmResolve: null,
    loading: true,
  };

  const api = (method, ...args) => window.nimi.call(method, ...args);

  // --- formatting ---------------------------------------------------------

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function formatTime(stamp) {
    if (!stamp) return "";
    const date = new Date(Number(stamp) * 1000);
    if (Number.isNaN(date.getTime())) return "";
    const now = new Date();
    const sameDay = date.toDateString() === now.toDateString();
    if (sameDay) {
      return date.toLocaleTimeString("zh-CN", {
        hour: "2-digit",
        minute: "2-digit",
      });
    }
    const sameYear = date.getFullYear() === now.getFullYear();
    return date.toLocaleDateString("zh-CN", {
      year: sameYear ? undefined : "numeric",
      month: "long",
      day: "numeric",
    });
  }

  function snippet(body) {
    const text = String(body || "")
      .replace(/```[\s\S]*?```/g, " ")
      .replace(/[#>*_`~\-\[\]()]/g, " ")
      .replace(/\s+/g, " ")
      .trim();
    return text.length > 82 ? text.slice(0, 82) + "…" : text || "空白笔记";
  }

  function inlineMarkdown(escaped) {
    const codes = [];
    let text = escaped.replace(/`([^`]+)`/g, (_, code) => {
      codes.push(code);
      return "\u0000C" + (codes.length - 1) + "\u0000";
    });
    text = text.replace(
      /\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g,
      '<a href="$2" target="_blank" rel="noreferrer">$1</a>'
    );
    text = text.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
    text = text.replace(/(^|[^*])\*([^*\n]+)\*/g, "$1<em>$2</em>");
    text = text.replace(/\u0000C(\d+)\u0000/g, (_, index) => {
      return "<code>" + codes[Number(index)] + "</code>";
    });
    return text;
  }

  function renderMarkdown(source) {
    const lines = String(source || "").replace(/\r\n?/g, "\n").split("\n");
    const out = [];
    let paragraph = [];
    let list = [];
    let quote = [];
    let code = [];
    let inCode = false;

    const flushParagraph = () => {
      if (!paragraph.length) return;
      out.push("<p>" + paragraph.map(inlineMarkdown).join("<br>") + "</p>");
      paragraph = [];
    };
    const flushList = () => {
      if (!list.length) return;
      out.push(
        "<ul>" +
          list.map((item) => "<li>" + inlineMarkdown(item) + "</li>").join("") +
          "</ul>"
      );
      list = [];
    };
    const flushQuote = () => {
      if (!quote.length) return;
      out.push(
        "<blockquote>" +
          quote.map(inlineMarkdown).join("<br>") +
          "</blockquote>"
      );
      quote = [];
    };
    const flushAll = () => {
      flushParagraph();
      flushList();
      flushQuote();
    };

    for (const line of lines) {
      const trimmed = line.trim();

      if (inCode) {
        if (trimmed.startsWith("```")) {
          out.push("<pre><code>" + escapeHtml(code.join("\n")) + "</code></pre>");
          code = [];
          inCode = false;
        } else {
          code.push(line);
        }
        continue;
      }

      if (trimmed.startsWith("```")) {
        flushAll();
        inCode = true;
        continue;
      }

      if (!trimmed) {
        flushAll();
        continue;
      }

      const heading = /^(#{1,3})\s+(.*)$/.exec(trimmed);
      if (heading) {
        flushAll();
        const level = heading[1].length;
        out.push(
          "<h" + level + ">" + inlineMarkdown(escapeHtml(heading[2])) +
            "</h" + level + ">"
        );
        continue;
      }

      if (/^(-{3,}|\*{3,}|_{3,})$/.test(trimmed)) {
        flushAll();
        out.push("<hr>");
        continue;
      }

      if (trimmed.startsWith("> ")) {
        flushParagraph();
        flushList();
        quote.push(escapeHtml(trimmed.slice(2)));
        continue;
      }

      if (/^[-*]\s+/.test(trimmed)) {
        flushParagraph();
        flushQuote();
        list.push(escapeHtml(trimmed.replace(/^[-*]\s+/, "")));
        continue;
      }

      flushList();
      flushQuote();
      paragraph.push(escapeHtml(trimmed));
    }

    if (inCode) {
      out.push("<pre><code>" + escapeHtml(code.join("\n")) + "</code></pre>");
    }
    flushAll();

    return out.join("\n") || '<p class="preview-empty">开始写作,预览会出现在这里。</p>';
  }

  // --- state helpers ------------------------------------------------------

  function currentNote() {
    return state.notes.find((note) => note.id === state.selectedId) || null;
  }

  function setStatus(text, kind) {
    els.status.dataset.state = kind || "saved";
    els.status.innerHTML = '<span class="status-dot"></span>' + escapeHtml(text);
  }

  function updateCount() {
    els.noteCount.textContent = state.notes.length + " 篇笔记";
  }

  function updateMeta(note) {
    els.wordCount.textContent =
      String(note && note.body ? note.body.replace(/\s+/g, "").length : 0) + " 字";
    els.updated.textContent =
      note && note.updatedAt ? "更新于 " + formatTime(note.updatedAt) : "";
  }

  function updateWindowTitle(note) {
    api("Shell.setTitle", note ? note.title : "").catch(() => {});
  }

  function filteredNotes() {
    const q = state.query.trim().toLowerCase();
    const notes = state.notes.slice().sort((a, b) => {
      return Number(b.updatedAt || 0) - Number(a.updatedAt || 0);
    });
    if (!q) return notes;
    return notes.filter((note) => {
      return (
        String(note.title || "").toLowerCase().includes(q) ||
        String(note.body || "").toLowerCase().includes(q)
      );
    });
  }

  function renderNoteList() {
    updateCount();
    const notes = filteredNotes();
    els.noteList.textContent = "";

    if (!notes.length) {
      const empty = document.createElement("div");
      empty.className = "note-item empty-result";
      empty.textContent = state.query ? "没有匹配的笔记" : "还没有笔记";
      els.noteList.appendChild(empty);
      return;
    }

    for (const note of notes) {
      const item = document.createElement("button");
      item.type = "button";
      item.className = "note-item" + (note.id === state.selectedId ? " active" : "");
      item.dataset.id = note.id;

      const title = document.createElement("div");
      title.className = "note-item-title";
      title.textContent = note.title || "无标题笔记";

      const preview = document.createElement("div");
      preview.className = "note-item-snippet";
      preview.textContent = snippet(note.body);

      const time = document.createElement("div");
      time.className = "note-item-time";
      time.textContent = formatTime(note.updatedAt);

      item.append(title, preview, time);
      els.noteList.appendChild(item);
    }
  }

  function renderPreview() {
    els.preview.innerHTML = renderMarkdown(els.editor.value);
  }

  function setEditorEnabled(enabled) {
    els.title.disabled = !enabled;
    els.editor.disabled = !enabled;
    els.export.disabled = !enabled;
    els.delete.disabled = !enabled;
    els.editorWrap.classList.toggle("hidden", !enabled);
    els.empty.classList.toggle("hidden", enabled);
  }

  function flushPendingSave(exceptId) {
    if (state.saveTimer) {
      clearTimeout(state.saveTimer);
      state.saveTimer = null;
    }
    const pending = state.dirtyNoteId;
    state.dirtyNoteId = null;
    if (pending && pending !== exceptId) {
      saveNoteById(pending);
    }
  }

  function selectNote(id) {
    if (id !== state.selectedId) flushPendingSave(id);
    const note = state.notes.find((item) => item.id === id);
    if (!note) {
      state.selectedId = null;
      setEditorEnabled(false);
      renderNoteList();
      return;
    }
    state.selectedId = id;
    els.title.value = note.title || "";
    els.editor.value = note.body || "";
    renderPreview();
    updateMeta(note);
    updateWindowTitle(note);
    setEditorEnabled(true);
    setStatus("已保存", "saved");
    renderNoteList();
  }

  // --- backend actions ----------------------------------------------------

  async function loadNotes(preferredId) {
    const list = await api("Notes.listNotes");
    state.notes = Array.isArray(list) ? list : [];
    state.loading = false;

    let target = null;
    if (preferredId && state.notes.some((note) => note.id === preferredId)) {
      target = preferredId;
    } else if (
      state.selectedId &&
      state.notes.some((note) => note.id === state.selectedId)
    ) {
      target = state.selectedId;
    } else if (state.notes.length) {
      target = state.notes[0].id;
    }

    renderNoteList();
    if (target) {
      selectNote(target);
    } else {
      state.selectedId = null;
      setEditorEnabled(false);
      renderNoteList();
    }
  }

  function markDirty() {
    const note = currentNote();
    if (!note) return;
    state.dirtyNoteId = note.id;
    setStatus("未保存", "dirty");
    if (state.saveTimer) clearTimeout(state.saveTimer);
    state.saveTimer = setTimeout(() => {
      state.saveTimer = null;
      const pending = state.dirtyNoteId;
      state.dirtyNoteId = null;
      if (pending) saveNoteById(pending);
    }, 450);
  }

  function saveNoteById(id) {
    const note = state.notes.find((item) => item.id === id);
    if (!note || state.loading) return Promise.resolve();

    const run = async () => {
      const isCurrent = state.selectedId === id;
      if (isCurrent) setStatus("保存中…", "saving");
      try {
        const updated = await api(
          "Notes.updateNote",
          note.id,
          note.title || "",
          note.body || ""
        );
        if (updated) {
          note.updatedAt = updated.updatedAt;
          if (state.selectedId === id) {
            updateMeta(note);
            updateWindowTitle(note);
          }
          renderNoteList();
        }
        if (state.selectedId === id) setStatus("已保存", "saved");
      } catch (error) {
        console.error(error);
        if (state.selectedId === id) setStatus("保存失败", "error");
      }
    };

    state.saveChain = state.saveChain.then(run, run);
    return state.saveChain;
  }

  function saveNow() {
    const note = currentNote();
    if (!note) return Promise.resolve();
    if (state.saveTimer) {
      clearTimeout(state.saveTimer);
      state.saveTimer = null;
    }
    state.dirtyNoteId = null;
    return saveNoteById(note.id);
  }

  async function newNote() {
    try {
      await saveNow();
      const note = await api("Notes.createNote", "无标题笔记");
      await loadNotes(note.id);
      els.title.focus();
      els.title.select();
      setStatus("已保存", "saved");
    } catch (error) {
      console.error(error);
      setStatus("新建失败", "error");
    }
  }

  async function importNote() {
    try {
      await saveNow();
      const note = await api("Notes.importNote");
      if (!note) {
        setStatus("已取消", "saved");
        return;
      }
      await loadNotes(note.id);
      setStatus("已导入", "saved");
    } catch (error) {
      console.error(error);
      setStatus("导入失败", "error");
    }
  }

  async function exportNote() {
    const note = currentNote();
    if (!note) return;
    try {
      await saveNow();
      const path = await api("Notes.exportNote", note.id);
      setStatus(path ? "已导出" : "已取消", "saved");
    } catch (error) {
      console.error(error);
      setStatus("导出失败", "error");
    }
  }

  async function removeNote() {
    const note = currentNote();
    if (!note) return;
    const label = note.title || "无标题笔记";
    if (!(await askConfirm(label))) return;
    try {
      flushPendingSave(null);
      await state.saveChain;
      await api("Notes.removeNote", note.id);
      state.selectedId = null;
      await loadNotes(null);
      setStatus("已删除", "saved");
    } catch (error) {
      console.error(error);
      setStatus("删除失败", "error");
    }
  }

  function focusSearch() {
    els.search.focus();
    els.search.select();
  }

  function askConfirm(label) {
    els.confirmTitle.textContent = '删除“' + label + '”?';
    els.confirm.classList.remove("hidden");
    els.confirmOk.focus();
    return new Promise((resolve) => {
      state.confirmResolve = resolve;
    });
  }

  function closeConfirm(value) {
    els.confirm.classList.add("hidden");
    const resolve = state.confirmResolve;
    state.confirmResolve = null;
    if (resolve) resolve(value);
  }

  // --- events -------------------------------------------------------------

  els.newNote.addEventListener("click", newNote);
  els.emptyNew.addEventListener("click", newNote);
  els.import.addEventListener("click", importNote);
  els.export.addEventListener("click", exportNote);
  els.delete.addEventListener("click", removeNote);
  els.confirmCancel.addEventListener("click", () => closeConfirm(false));
  els.confirmOk.addEventListener("click", () => closeConfirm(true));
  els.confirm.addEventListener("click", (event) => {
    if (event.target === els.confirm) closeConfirm(false);
  });

  els.search.addEventListener("input", () => {
    state.query = els.search.value;
    renderNoteList();
  });

  els.noteList.addEventListener("click", (event) => {
    const item = event.target.closest(".note-item[data-id]");
    if (item) selectNote(item.dataset.id);
  });

  els.title.addEventListener("input", () => {
    const note = currentNote();
    if (!note) return;
    note.title = els.title.value;
    renderNoteList();
    updateWindowTitle(note);
    markDirty();
  });

  els.editor.addEventListener("input", () => {
    const note = currentNote();
    if (!note) return;
    note.body = els.editor.value;
    renderPreview();
    updateMeta(note);
    markDirty();
  });

  window.addEventListener("blur", () => {
    if (state.saveTimer) saveNow();
  });

  document.addEventListener("visibilitychange", () => {
    if (document.hidden && state.saveTimer) saveNow();
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" &&
        !els.confirm.classList.contains("hidden")) {
      closeConfirm(false);
    }
  });

  window.nimiNotes = {
    newNote,
    saveNow,
    importNote,
    exportNote,
    focusSearch,
    state,
  };

  setStatus("载入中…", "saving");
  loadNotes(null).catch((error) => {
    console.error(error);
    setStatus("载入失败", "error");
    setEditorEnabled(false);
  });
})();
