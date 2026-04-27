// ── Hash-based SPA 路由 ──

class Router {
  constructor() {
    this._routes = [];
    this._otherwise = null;
  }

  on(pattern, handler) {
    // 解析路径参数 :id, :action
    const paramNames = [];
    const regexStr = pattern.replace(/:([^/]+)/g, (_, name) => {
      paramNames.push(name);
      return '([^/]+)';
    });
    this._routes.push({
      pattern,
      regex: new RegExp('^' + regexStr + '$'),
      paramNames,
      handler,
    });
  }

  otherwise(handler) {
    this._otherwise = handler;
  }

  start() {
    window.addEventListener('hashchange', () => this._handle());
    if (location.hash) this._handle();
  }

  _handle() {
    const hash = location.hash || '#/dashboard';
    // 去掉末尾斜杠
    const cleanHash = hash.replace(/\/$/, '') || '#/dashboard';

    for (const route of this._routes) {
      const match = cleanHash.match(route.regex);
      if (match) {
        const params = {};
        route.paramNames.forEach((name, i) => {
          params[name] = match[i + 1];
        });
        route.handler(params);
        return;
      }
    }

    if (this._otherwise) {
      this._otherwise();
    }
  }
}

// 编程式导航
export function navigate(hash) {
  location.hash = hash;
}

export const router = new Router();
