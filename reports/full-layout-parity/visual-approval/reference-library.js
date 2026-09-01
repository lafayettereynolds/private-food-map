(() => {
  "use strict";

  const DATABASE_NAME = "tastemap-lafayette-visual-approval";
  const DATABASE_VERSION = 1;
  const STORE_NAME = "references";
  const ALLOWED_MIME_TYPES = new Set(["image/png", "image/jpeg", "image/webp"]);

  function requestResult(request) {
    return new Promise((resolve, reject) => {
      request.addEventListener("success", () => resolve(request.result), { once: true });
      request.addEventListener("error", () => reject(request.error || new Error("IndexedDB 请求失败")), { once: true });
    });
  }

  function transactionComplete(transaction) {
    return new Promise((resolve, reject) => {
      transaction.addEventListener("complete", resolve, { once: true });
      transaction.addEventListener("abort", () => reject(transaction.error || new Error("IndexedDB 事务已中止")), { once: true });
      transaction.addEventListener("error", () => reject(transaction.error || new Error("IndexedDB 事务失败")), { once: true });
    });
  }

  function openDatabase() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DATABASE_NAME, DATABASE_VERSION);
      request.addEventListener("upgradeneeded", () => {
        const database = request.result;
        const store = database.objectStoreNames.contains(STORE_NAME)
          ? request.transaction.objectStore(STORE_NAME)
          : database.createObjectStore(STORE_NAME, { keyPath: "id" });
        if (!store.indexNames.contains("itemId")) store.createIndex("itemId", "itemId", { unique: false });
        if (!store.indexNames.contains("createdAt")) store.createIndex("createdAt", "createdAt", { unique: false });
      });
      request.addEventListener("success", () => resolve(request.result), { once: true });
      request.addEventListener("error", () => reject(request.error || new Error("无法打开本机参考图库")), { once: true });
      request.addEventListener("blocked", () => reject(new Error("参考图库升级被其他页面阻止，请关闭旧审批台后重试")), { once: true });
    });
  }

  function referenceID() {
    if (crypto.randomUUID) return crypto.randomUUID();
    return `reference-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  }

  function validateImageFile(file) {
    if (!(file instanceof Blob)) throw new Error("请选择有效图片文件");
    if (!ALLOWED_MIME_TYPES.has(file.type)) throw new Error("只支持 PNG、JPG/JPEG 或 WEBP 图片");
  }

  async function listAll() {
    const database = await openDatabase();
    try {
      const transaction = database.transaction(STORE_NAME, "readonly");
      const records = await requestResult(transaction.objectStore(STORE_NAME).getAll());
      await transactionComplete(transaction);
      return records.sort((left, right) => left.createdAt.localeCompare(right.createdAt));
    } finally {
      database.close();
    }
  }

  async function listForItem(itemId) {
    const database = await openDatabase();
    try {
      const transaction = database.transaction(STORE_NAME, "readonly");
      const records = await requestResult(transaction.objectStore(STORE_NAME).index("itemId").getAll(itemId));
      await transactionComplete(transaction);
      return records.sort((left, right) => left.createdAt.localeCompare(right.createdAt));
    } finally {
      database.close();
    }
  }

  async function addFiles(itemId, files) {
    const acceptedFiles = Array.from(files || []);
    if (!acceptedFiles.length) return [];
    acceptedFiles.forEach(validateImageFile);

    const now = new Date().toISOString();
    const records = acceptedFiles.map((file, index) => ({
      id: referenceID(),
      itemId,
      title: file.name,
      filename: file.name,
      mimeType: file.type,
      size: file.size,
      blob: file.slice(0, file.size, file.type),
      purpose: "wholePage",
      strength: "direction",
      regionIds: [],
      isFinal: false,
      notes: "",
      createdAt: new Date(Date.parse(now) + index).toISOString(),
      updatedAt: now,
    }));

    const database = await openDatabase();
    try {
      const transaction = database.transaction(STORE_NAME, "readwrite");
      const store = transaction.objectStore(STORE_NAME);
      records.forEach((record) => store.put(record));
      await transactionComplete(transaction);
      return records;
    } finally {
      database.close();
    }
  }

  async function update(id, changes) {
    const database = await openDatabase();
    try {
      const transaction = database.transaction(STORE_NAME, "readwrite");
      const store = transaction.objectStore(STORE_NAME);
      const record = await requestResult(store.get(id));
      if (!record) throw new Error("找不到要更新的参考图");
      const updated = { ...record, ...changes, id, updatedAt: new Date().toISOString() };
      store.put(updated);
      await transactionComplete(transaction);
      return updated;
    } finally {
      database.close();
    }
  }

  async function replaceImage(id, file) {
    validateImageFile(file);
    return update(id, {
      filename: file.name,
      mimeType: file.type,
      size: file.size,
      blob: file.slice(0, file.size, file.type),
    });
  }

  async function remove(id) {
    const database = await openDatabase();
    try {
      const transaction = database.transaction(STORE_NAME, "readwrite");
      transaction.objectStore(STORE_NAME).delete(id);
      await transactionComplete(transaction);
    } finally {
      database.close();
    }
  }

  function sanitizePathSegment(value, fallback) {
    const sanitized = String(value || "")
      .normalize("NFKC")
      .replace(/[\\/:*?"<>|\u0000-\u001F]/g, "-")
      .replace(/\s+/g, "-")
      .replace(/-+/g, "-")
      .replace(/^-|-$/g, "")
      .slice(0, 96);
    return sanitized || fallback;
  }

  function extensionFor(record) {
    if (record.mimeType === "image/png") return ".png";
    if (record.mimeType === "image/webp") return ".webp";
    return ".jpg";
  }

  function exportPathFor(record, index) {
    const folder = sanitizePathSegment(record.itemId, "page");
    const title = sanitizePathSegment(record.title || record.filename, `reference-${index + 1}`);
    const titleWithoutExtension = title.replace(/\.(png|jpe?g|webp)$/i, "");
    return `references/${folder}/${String(index + 1).padStart(2, "0")}-${titleWithoutExtension}${extensionFor(record)}`;
  }

  const CRC_TABLE = (() => {
    const table = new Uint32Array(256);
    for (let index = 0; index < 256; index += 1) {
      let current = index;
      for (let bit = 0; bit < 8; bit += 1) current = (current & 1) ? (0xEDB88320 ^ (current >>> 1)) : (current >>> 1);
      table[index] = current >>> 0;
    }
    return table;
  })();

  function crc32(bytes) {
    let crc = 0xFFFFFFFF;
    for (const byte of bytes) crc = CRC_TABLE[(crc ^ byte) & 0xFF] ^ (crc >>> 8);
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  function dosTimestamp(date) {
    const year = Math.max(1980, date.getFullYear());
    return {
      time: (date.getHours() << 11) | (date.getMinutes() << 5) | Math.floor(date.getSeconds() / 2),
      date: ((year - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate(),
    };
  }

  function writeUInt16(view, offset, value) { view.setUint16(offset, value, true); }
  function writeUInt32(view, offset, value) { view.setUint32(offset, value >>> 0, true); }

  async function bytesFor(data) {
    if (data instanceof Uint8Array) return data;
    if (data instanceof Blob) return new Uint8Array(await data.arrayBuffer());
    return new TextEncoder().encode(String(data));
  }

  async function createZip(entries) {
    const localParts = [];
    const centralParts = [];
    let offset = 0;

    for (const entry of entries) {
      const nameBytes = new TextEncoder().encode(entry.path);
      const dataBytes = await bytesFor(entry.data);
      const checksum = crc32(dataBytes);
      const stamp = dosTimestamp(entry.date || new Date());

      const localHeader = new Uint8Array(30 + nameBytes.length);
      const localView = new DataView(localHeader.buffer);
      writeUInt32(localView, 0, 0x04034B50);
      writeUInt16(localView, 4, 20);
      writeUInt16(localView, 6, 0x0800);
      writeUInt16(localView, 8, 0);
      writeUInt16(localView, 10, stamp.time);
      writeUInt16(localView, 12, stamp.date);
      writeUInt32(localView, 14, checksum);
      writeUInt32(localView, 18, dataBytes.length);
      writeUInt32(localView, 22, dataBytes.length);
      writeUInt16(localView, 26, nameBytes.length);
      writeUInt16(localView, 28, 0);
      localHeader.set(nameBytes, 30);
      localParts.push(localHeader, dataBytes);

      const centralHeader = new Uint8Array(46 + nameBytes.length);
      const centralView = new DataView(centralHeader.buffer);
      writeUInt32(centralView, 0, 0x02014B50);
      writeUInt16(centralView, 4, 20);
      writeUInt16(centralView, 6, 20);
      writeUInt16(centralView, 8, 0x0800);
      writeUInt16(centralView, 10, 0);
      writeUInt16(centralView, 12, stamp.time);
      writeUInt16(centralView, 14, stamp.date);
      writeUInt32(centralView, 16, checksum);
      writeUInt32(centralView, 20, dataBytes.length);
      writeUInt32(centralView, 24, dataBytes.length);
      writeUInt16(centralView, 28, nameBytes.length);
      writeUInt16(centralView, 30, 0);
      writeUInt16(centralView, 32, 0);
      writeUInt16(centralView, 34, 0);
      writeUInt16(centralView, 36, 0);
      writeUInt32(centralView, 38, 0);
      writeUInt32(centralView, 42, offset);
      centralHeader.set(nameBytes, 46);
      centralParts.push(centralHeader);

      offset += localHeader.length + dataBytes.length;
    }

    const centralSize = centralParts.reduce((total, part) => total + part.length, 0);
    const end = new Uint8Array(22);
    const endView = new DataView(end.buffer);
    writeUInt32(endView, 0, 0x06054B50);
    writeUInt16(endView, 4, 0);
    writeUInt16(endView, 6, 0);
    writeUInt16(endView, 8, entries.length);
    writeUInt16(endView, 10, entries.length);
    writeUInt32(endView, 12, centralSize);
    writeUInt32(endView, 16, offset);
    writeUInt16(endView, 20, 0);

    return new Blob([...localParts, ...centralParts, end], { type: "application/zip" });
  }

  async function createApprovalPackage(approval) {
    const references = await listAll();
    const exportedReferences = references.map((record, index) => ({
      id: record.id,
      itemId: record.itemId,
      title: record.title,
      filename: record.filename,
      mimeType: record.mimeType,
      size: record.size,
      purpose: record.purpose,
      strength: record.strength,
      regionIds: record.regionIds || [],
      isFinal: Boolean(record.isFinal),
      notes: record.notes || "",
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      path: exportPathFor(record, index),
    }));

    const payload = {
      ...approval,
      exportedAt: new Date().toISOString(),
      references: exportedReferences,
    };
    const readme = [
      "# Taste Map — Lafayette 视觉审批包",
      "",
      "- `approval.json`：页面决定、区域决定、冻结状态、备注和参考图元数据。",
      "- `references/`：Lafayette 本机上传的原始参考图片。",
      "- 后续 Codex 执行时，若参考图标记为 `geometry`、`highFidelity` 或 `isFinal: true`，必须先查看图片再实施。",
      "- 本包由本机审批工具生成，没有上传到 Taste Map、Production 或云端。",
      "",
    ].join("\n");
    const entries = [
      { path: "approval.json", data: JSON.stringify(payload, null, 2) },
      { path: "README.md", data: readme },
      ...references.map((record, index) => ({ path: exportedReferences[index].path, data: record.blob })),
    ];
    return { blob: await createZip(entries), payload };
  }

  window.LafayetteReferenceLibrary = Object.freeze({
    allowedMimeTypes: ALLOWED_MIME_TYPES,
    listAll,
    listForItem,
    addFiles,
    update,
    replaceImage,
    remove,
    createApprovalPackage,
  });
})();
