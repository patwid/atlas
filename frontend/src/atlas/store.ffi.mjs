// IndexedDB access for the device database (ADR 0019). No logic beyond reading and writing:
// what to store and when is decided in Gleam. Every function reports with callback(ok, value);
// ok is false when IndexedDB failed (quota, blocked, closed), and the value is then undefined.
import { toList } from "../gleam.mjs"

let database = null

const wrap = (request) =>
  new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })

const finished = (tx) =>
  new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error ?? new Error("transaction aborted"))
  })

const report = (callback, work) =>
  work().then(
    (value) => callback(true, value),
    (error) => {
      console.warn("store:", error)
      callback(false, undefined)
    },
  )

const keyOf = (collection, id) => `${collection}/${id}`

export function open(name, callback) {
  const request = indexedDB.open(name, 1)
  request.onupgradeneeded = () => {
    const db = request.result
    const records = db.createObjectStore("records", { keyPath: "key" })
    records.createIndex("collection", "collection")
    db.createObjectStore("meta", { keyPath: "key" })
  }
  request.onsuccess = () => {
    database = request.result
    database.onversionchange = () => database.close()
    callback(true)
  }
  request.onerror = () => callback(false)
  request.onblocked = () => callback(false)
}

export function putRecords(collection, records, callback) {
  report(callback, async () => {
    const tx = database.transaction("records", "readwrite")
    const store = tx.objectStore("records")
    for (const data of records.toArray()) {
      store.put({ key: keyOf(collection, data.id), collection, id: data.id, data })
    }
    await finished(tx)
    return true
  })
}

// Inserts the record or merges the patch (JSON text) into the stored one, field by field.
export function mergeJson(collection, id, patchText, callback) {
  report(callback, async () => {
    const patch = JSON.parse(patchText)
    const tx = database.transaction("records", "readwrite")
    const store = tx.objectStore("records")
    const existing = await wrap(store.get(keyOf(collection, id)))
    const data = { ...(existing?.data ?? {}), ...patch, id }
    store.put({ key: keyOf(collection, id), collection, id, data })
    await finished(tx)
    return true
  })
}

export function getRecord(collection, id, callback) {
  report(callback, async () => {
    const found = await wrap(database.transaction("records").objectStore("records").get(keyOf(collection, id)))
    return found ? found.data : null
  })
}

export function getAll(collection, callback) {
  report(callback, async () => {
    const index = database.transaction("records").objectStore("records").index("collection")
    const rows = await wrap(index.getAll(collection))
    return toList(rows.map((row) => row.data))
  })
}

export function deleteRecord(collection, id, callback) {
  report(callback, async () => {
    const tx = database.transaction("records", "readwrite")
    tx.objectStore("records").delete(keyOf(collection, id))
    await finished(tx)
    return true
  })
}

// Deletes the collection's records whose ID is in neither list (a full resync found them gone on the server).
export function deleteMissing(collection, keep, protectedIds, callback) {
  report(callback, async () => {
    const keepSet = new Set([...keep.toArray(), ...protectedIds.toArray()])
    const tx = database.transaction("records", "readwrite")
    const store = tx.objectStore("records")
    const rows = await wrap(store.index("collection").getAll(collection))
    let removed = 0
    for (const row of rows) {
      if (!keepSet.has(row.id)) {
        store.delete(row.key)
        removed++
      }
    }
    await finished(tx)
    return removed
  })
}

export function getMeta(key, callback) {
  report(callback, async () => {
    const found = await wrap(database.transaction("meta").objectStore("meta").get(key))
    return found ? found.value : ""
  })
}

export function putMeta(key, value, callback) {
  report(callback, async () => {
    const tx = database.transaction("meta", "readwrite")
    tx.objectStore("meta").put({ key, value })
    await finished(tx)
    return true
  })
}

export function clearAll(callback) {
  report(callback, async () => {
    const tx = database.transaction(["records", "meta"], "readwrite")
    tx.objectStore("records").clear()
    tx.objectStore("meta").clear()
    await finished(tx)
    return true
  })
}

export function requestPersistence(callback) {
  if (navigator.storage && navigator.storage.persist) {
    navigator.storage.persist().then((granted) => callback(granted), () => callback(false))
  } else {
    callback(false)
  }
}
