import { api } from '../api.js';

export async function renderOrders() {
  const main = document.getElementById('mainContent');
  main.innerHTML = '<div class="page-loader"><div class="spinner"></div></div>';

  document.querySelectorAll('.nav-link').forEach(a => {
    a.classList.toggle('active', a.getAttribute('data-route') === 'orders');
  });

  try {
    const result = await api.get('/api/orders', { limit: 100 });
    const warehouses = await api.get('/api/warehouses');
    const whName = id => { const w = warehouses.find(x => x.id === id); return w ? w.name : '未知'; };

    main.innerHTML = `
      <div class="page-title">
        <i class="fa-solid fa-file-invoice" style="color:var(--teal)"></i>
        单据列表
        <span class="sub">${result.pagination.total} 张</span>
      </div>
      ${result.data.length ? `
        <div class="card"><div class="table-wrap"><table><thead><tr>
          <th>日期</th><th>类型</th><th>客户</th><th>仓库</th><th>货物</th><th>总金额</th><th>同步</th>
        </tr></thead><tbody>
        ${result.data.map(o => {
          const typeBadge = o.type === 'inbound' ? '<span class="badge badge-inbound">入库</span>'
            : o.type === 'outbound' ? '<span class="badge badge-outbound">出库</span>'
            : '<span class="badge" style="background:#fef3c7;color:#92400e">进货</span>';
          const syncBadge = o.syncStatus === 'synced' ? '<span class="badge badge-synced">已同步</span>'
            : '<span class="badge badge-pending">未同步</span>';
          const items = (o.items || []).map(i => i.itemName).filter((v,i,a) => a.indexOf(v)===i).join('、');
          const d = new Date(o.timestamp);
          const dateStr = d.getFullYear() + '-' + String(d.getMonth()+1).padStart(2,'0') + '-' + String(d.getDate()).padStart(2,'0');
          return `<tr style="cursor:pointer" onclick="location.hash='#/orders/${o.id}'">
            <td>${dateStr}</td><td>${typeBadge}</td>
            <td><strong>${esc(o.partnerName)}</strong></td>
            <td>${esc(whName(o.warehouseId))}</td>
            <td>${esc(items||'-')}</td>
            <td style="font-weight:600;color:var(--teal-dark)">¥${(o.totalAmount||0).toFixed(2)}</td>
            <td>${syncBadge}</td>
          </tr>`;
        }).join('')}
        </tbody></table></div></div>
      ` : '<div class="empty-state"><i class="fa-solid fa-inbox"></i><p>暂无单据</p></div>'}
    `;
  } catch (e) {
    main.innerHTML = '<div class="empty-state"><p>加载失败: ' + esc(e.message) + '</p></div>';
  }
}

function esc(s) { return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
