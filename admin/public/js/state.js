// ── 响应式状态管理 ──

class Store {
  constructor() {
    this._state = {
      warehouses: [],
      stats: null,
    };
    this._listeners = [];
  }

  getState() { return this._state; }

  setState(partial) {
    Object.assign(this._state, partial);
    this._notify();
  }

  subscribe(fn) {
    this._listeners.push(fn);
    return () => {
      this._listeners = this._listeners.filter(l => l !== fn);
    };
  }

  _notify() {
    this._listeners.forEach(fn => fn(this._state));
  }

  // 加载仓库列表
  async loadWarehouses() {
    try {
      const warehouses = await (await fetch('/api/warehouses')).json();
      this.setState({ warehouses });
      return warehouses;
    } catch (e) {
      console.error('加载仓库失败:', e);
      return [];
    }
  }

  // 加载统计数据
  async loadStats() {
    try {
      const stats = await (await fetch('/api/stats')).json();
      this.setState({ stats });
      return stats;
    } catch (e) {
      console.error('加载统计失败:', e);
      return null;
    }
  }

  // 获取仓库名
  getWarehouseName(id) {
    const wh = this._state.warehouses.find(w => w.id === id);
    return wh ? wh.name : '未知仓库';
  }
}

export const store = new Store();
