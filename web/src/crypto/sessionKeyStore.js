/**
 * IndexedDB 安全儲存 Session Key
 *
 * 使用 IndexedDB 儲存解密後的 Session Key，提供跨分頁持久化。
 * 若 IndexedDB 不可用，降級至 sessionStorage（資料不跨分頁保留）。
 *
 * DB: ChatWMEX_KeyStore
 * Object Store: session_keys
 * Key path: id (固定為 "current")
 */

const DB_NAME = 'ChatWMEX_KeyStore';
const DB_VERSION = 1;
const STORE_NAME = 'session_keys';
const CURRENT_KEY_ID = 'current';

/**
 * 開啟（或建立）IndexedDB 資料庫。
 * @returns {Promise<IDBDatabase>}
 */
function openDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onupgradeneeded = (event) => {
      const db = event.target.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME, { keyPath: 'id' });
      }
    };

    request.onsuccess = (event) => resolve(event.target.result);
    request.onerror = (event) => reject(event.target.error);
  });
}

/**
 * 儲存 Session Key 至 IndexedDB。
 * 若 IndexedDB 不可用則降級至 sessionStorage。
 *
 * @param {string} sessionKeyBase64 — base64 編碼的 Session Key
 * @returns {Promise<void>}
 */
export async function saveSessionKey(sessionKeyBase64) {
  try {
    const db = await openDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readwrite');
      const store = tx.objectStore(STORE_NAME);
      store.put({ id: CURRENT_KEY_ID, key: sessionKeyBase64, updatedAt: Date.now() });
      tx.oncomplete = () => resolve();
      tx.onerror = (event) => reject(event.target.error);
    });
  } catch {
    // 降級至 sessionStorage
    console.warn('IndexedDB unavailable, falling back to sessionStorage');
    if (typeof sessionStorage !== 'undefined') {
      sessionStorage.setItem('session_key', sessionKeyBase64);
    }
  }
}

/**
 * 從 IndexedDB 讀取 Session Key。
 * 若 IndexedDB 不可用則從 sessionStorage 讀取。
 *
 * @returns {Promise<string|null>} base64 編碼的 Session Key，或 null
 */
export async function getSessionKey() {
  try {
    const db = await openDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readonly');
      const store = tx.objectStore(STORE_NAME);
      const request = store.get(CURRENT_KEY_ID);
      request.onsuccess = () => resolve(request.result?.key ?? null);
      request.onerror = (event) => reject(event.target.error);
    });
  } catch {
    console.warn('IndexedDB unavailable, falling back to sessionStorage');
    if (typeof sessionStorage !== 'undefined') {
      return sessionStorage.getItem('session_key') ?? null;
    }
    return null;
  }
}

/**
 * 清除 IndexedDB 與 sessionStorage 中的 Session Key。
 * 用於取消連結或登出時清理。
 *
 * @returns {Promise<void>}
 */
export async function clearSessionKey() {
  // 同時清除兩處，確保無殘留
  if (typeof sessionStorage !== 'undefined') {
    sessionStorage.removeItem('session_key');
  }
  try {
    const db = await openDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readwrite');
      const store = tx.objectStore(STORE_NAME);
      store.delete(CURRENT_KEY_ID);
      tx.oncomplete = () => resolve();
      tx.onerror = (event) => reject(event.target.error);
    });
  } catch {
    // sessionStorage already cleared above
  }
}

/**
 * 檢查是否已有 Session Key。
 * @returns {Promise<boolean>}
 */
export async function hasSessionKey() {
  const key = await getSessionKey();
  return key !== null;
}
