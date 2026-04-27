// ── REST API 封装 ──

class Api {
  async request(method, path, body = null, params = {}) {
    const url = new URL(path, location.origin);
    Object.entries(params).forEach(([k, v]) => {
      if (v !== null && v !== undefined && v !== '') url.searchParams.set(k, v);
    });

    const opts = { method, headers: { 'Content-Type': 'application/json; charset=utf-8', 'Accept': 'application/json; charset=utf-8' } };
    if (body) opts.body = JSON.stringify(body);

    const res = await fetch(url, opts);
    const data = await res.json();

    if (!res.ok) {
      const err = new Error(data.error || '请求失败');
      err.status = res.status;
      throw err;
    }
    return data;
  }

  get(path, params) { return this.request('GET', path, null, params); }
  post(path, body) { return this.request('POST', path, body); }
  put(path, body) { return this.request('PUT', path, body); }
  del(path) { return this.request('DELETE', path); }
}

export const api = new Api();
