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

export async function renderOrderDetail(id) {
  const main = document.getElementById('mainContent');
  main.innerHTML = '<div class="page-loader"><div class="spinner"></div></div>';
  try {
    const o = await api.get('/api/orders/' + id);
    const warehouses = await api.get('/api/warehouses');
    const whName = wid => { const w = warehouses.find(x => x.id === wid); return w ? w.name : '未知'; };
    const typeBadge = o.type === 'inbound' ? '<span class="badge badge-inbound">入库</span>'
      : o.type === 'outbound' ? '<span class="badge badge-outbound">出库</span>'
      : '<span class="badge" style="background:#fef3c7;color:#92400e">进货</span>';

    main.innerHTML = `
      <div class="page-title"><i class="fa-solid fa-file-invoice" style="color:var(--teal)"></i> 单据详情 <span class="sub">${esc(o.partnerName)}</span></div>
      <div class="voucher-card">
        <div class="voucher-header"><div>${typeBadge}</div><div style="text-align:right"><div class="amount-label">总金额</div><div class="amount-large">¥ ${(o.totalAmount||0).toFixed(2)}</div></div></div>
        <div class="voucher-section">
          <div class="voucher-section-title">基本信息</div>
          <div class="voucher-row"><span class="voucher-label">日期</span><span class="voucher-value">${new Date(o.timestamp).toLocaleDateString('zh-CN')}</span></div>
          <div class="voucher-row"><span class="voucher-label">客户</span><span class="voucher-value">${esc(o.partnerName)}</span></div>
          <div class="voucher-row"><span class="voucher-label">仓库</span><span class="voucher-value">${esc(whName(o.warehouseId))}</span></div>
          <div class="voucher-row"><span class="voucher-label">备注</span><span class="voucher-value">${esc(o.remark||'—')}</span></div>
        </div>
        <div class="voucher-section">
          <div class="voucher-section-title">货物明细（${(o.items||[]).length} 项）</div>
          ${(o.items||[]).map((it,i) => `
            <div class="voucher-row"><span class="voucher-label">${i+1}. ${esc(it.itemName)}</span><span class="voucher-value" style="font-family:var(--font-mono)">${(it.quantity||0).toFixed(1)}kg × ¥${(it.unitPrice||0).toFixed(2)}/吨 = ¥${((it.quantity/1000)*it.unitPrice).toFixed(2)}</span></div>
            ${it.grossWeight>0 ? '<div class="voucher-row"><span class="voucher-label" style="font-size:11px;color:grey">毛重/扣皮</span><span class="voucher-value" style="font-size:11px">' + it.grossWeight.toFixed(1) + 'kg / ' + (it.tareWeight||0).toFixed(1) + 'kg</span></div>' : ''}
          `).join('')}
        </div>
        ${(o.fees||[]).length ? `
          <div class="voucher-section">
            <div class="voucher-section-title">额外费用（${o.fees.length} 项）</div>
            ${o.fees.map(f => '<div class="voucher-row"><span class="voucher-label">' + esc(f.feeName) + '</span><span class="voucher-value" style="font-family:var(--font-mono)">¥' + (f.amount||0).toFixed(2) + '</span></div>').join('')}
          </div>
        ` : ''}
      </div>
      <div style="text-align:center;margin-top:16px"><a class="btn btn-outline" href="#/orders">返回列表</a></div>
    `;
  } catch (e) {
    main.innerHTML = '<div class="empty-state"><p>加载失败: ' + esc(e.message) + '</p></div>';
  }
}

function esc(s) { return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
