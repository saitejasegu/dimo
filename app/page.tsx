"use client";

import { FormEvent, ReactNode, useMemo, useState } from "react";

type View = "home" | "activity" | "stats" | "recurring" | "budgets";
type Transaction = { id: number; merchant: string; category: string; time: string; day: string; amount: number; featured?: boolean };
type Recurring = { id: number; merchant: string; due: string; amount: number; paused?: boolean; urgent?: boolean };

const navItems: { id: View; label: string; icon: string }[] = [
  { id: "home", label: "Overview", icon: "⌂" },
  { id: "activity", label: "Activity", icon: "↕" },
  { id: "stats", label: "Stats", icon: "▥" },
  { id: "recurring", label: "Recurring", icon: "↻" },
  { id: "budgets", label: "Budgets", icon: "◉" },
];

const initialTransactions: Transaction[] = [
  { id: 1, merchant: "Blue Tokai Coffee", category: "Dining", time: "8:42 AM", day: "Today", amount: 280, featured: true },
  { id: 2, merchant: "Swiggy", category: "Dining", time: "1:15 PM", day: "Today", amount: 430 },
  { id: 3, merchant: "Auto Rickshaw", category: "Transit", time: "6:05 PM", day: "Today", amount: 300 },
  { id: 4, merchant: "BigBasket", category: "Groceries", time: "11:20 AM", day: "Yesterday", amount: 1890 },
  { id: 5, merchant: "Netflix", category: "Bills", time: "9:00 AM", day: "Yesterday", amount: 649, featured: true },
  { id: 6, merchant: "Metro Recharge", category: "Transit", time: "8:10 AM", day: "Sunday, Jul 6", amount: 600 },
  { id: 7, merchant: "Nykaa", category: "Shopping", time: "4:40 PM", day: "Sunday, Jul 6", amount: 2280 },
  { id: 8, merchant: "Zepto", category: "Groceries", time: "7:32 PM", day: "Saturday, Jul 5", amount: 740 },
  { id: 9, merchant: "Uber", category: "Transit", time: "9:48 PM", day: "Saturday, Jul 5", amount: 315 },
];

const initialRecurring: Recurring[] = [
  { id: 1, merchant: "Electricity — BESCOM", due: "Due Jul 10 · in 2 days", amount: 1480, urgent: true },
  { id: 2, merchant: "Airtel Postpaid", due: "Due Jul 12 · monthly", amount: 599 },
  { id: 3, merchant: "ACT Fibernet", due: "Due Jul 14 · monthly", amount: 1131 },
  { id: 4, merchant: "Gym — Cult.fit", due: "Due Jul 18 · monthly", amount: 1299 },
  { id: 5, merchant: "Spotify Duo", due: "Due Jul 21 · monthly", amount: 149 },
  { id: 6, merchant: "Rent", due: "Due Aug 1 · monthly", amount: 18000 },
  { id: 7, merchant: "Hotstar", due: "Due Jul 25 · monthly", amount: 299, paused: true },
];

const limits: Record<string, number> = { Dining: 4000, Groceries: 6000, Bills: 3000, Transit: 2500, Shopping: 5000 };
const money = (n: number) => `₹${n.toLocaleString("en-IN")}`;

function Icon({ children, active = false }: { children: ReactNode; active?: boolean }) {
  return <span className={`nav-icon ${active ? "active" : ""}`} aria-hidden="true">{children}</span>;
}

function MerchantMark({ featured = false }: { featured?: boolean }) {
  return <span className={`merchant-mark ${featured ? "featured" : ""}`} aria-hidden="true"><span /></span>;
}

function SectionHeading({ title, action, onAction }: { title: string; action?: string; onAction?: () => void }) {
  return <div className="section-heading"><h2>{title}</h2>{action && <button className="text-button" onClick={onAction}>{action}</button>}</div>;
}

function TransactionRow({ item, compact = false, onOpen }: { item: Transaction; compact?: boolean; onOpen: () => void }) {
  return (
    <button className={`transaction-row ${compact ? "compact" : ""}`} onClick={onOpen}>
      <MerchantMark featured={item.featured} />
      <span className="row-copy"><strong>{item.merchant}</strong><small>{item.category} · {item.time}</small></span>
      {!compact && <span className="row-day">{item.day}</span>}
      <strong className="amount">−{money(item.amount)}</strong>
    </button>
  );
}

function RecurringRow({ item, onToggle, compact = false }: { item: Recurring; onToggle: () => void; compact?: boolean }) {
  return (
    <button className={`recurring-row ${item.paused ? "paused" : ""} ${compact ? "compact" : ""}`} onClick={onToggle}>
      <MerchantMark featured={item.urgent} />
      <span className="row-copy"><strong>{item.merchant}</strong><small className={item.urgent && !item.paused ? "urgent" : ""}>{item.paused ? "Paused" : item.due}</small></span>
      {!compact && <span className={`status-pill ${item.paused ? "off" : ""}`}>{item.paused ? "Paused" : "Active"}</span>}
      <strong className="amount">{money(item.amount)}</strong>
    </button>
  );
}

function Dashboard() {
  const [view, setView] = useState<View>("home");
  const [transactions, setTransactions] = useState(initialTransactions);
  const [recurring, setRecurring] = useState(initialRecurring);
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState("All");
  const [range, setRange] = useState("6M");
  const [detail, setDetail] = useState<Transaction | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [name, setName] = useState("");
  const [amount, setAmount] = useState("");
  const [category, setCategory] = useState("Dining");
  const [toast, setToast] = useState("");
  const [account, setAccount] = useState(false);

  const totalSpent = transactions.reduce((sum, t) => sum + t.amount, 0);
  const totalLimit = Object.values(limits).reduce((sum, value) => sum + value, 0);
  const budgetLeft = totalLimit - totalSpent;
  const recurringTotal = recurring.filter(r => !r.paused).reduce((sum, r) => sum + r.amount, 0);
  const categories = ["All", ...Object.keys(limits)];

  const filtered = useMemo(() => transactions.filter(t =>
    (filter === "All" || t.category === filter) &&
    (!query || `${t.merchant} ${t.category}`.toLowerCase().includes(query.toLowerCase()))
  ), [transactions, filter, query]);

  const categoryTotals = useMemo(() => Object.keys(limits).map(categoryName => ({
    name: categoryName,
    spent: transactions.filter(t => t.category === categoryName).reduce((sum, t) => sum + t.amount, 0),
    limit: limits[categoryName],
  })).sort((a, b) => b.spent - a.spent), [transactions]);

  const notify = (message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(""), 1800);
  };

  const toggleRecurring = (id: number) => {
    const item = recurring.find(r => r.id === id);
    setRecurring(list => list.map(r => r.id === id ? { ...r, paused: !r.paused } : r));
    if (item) notify(`${item.merchant} ${item.paused ? "resumed" : "paused"}`);
  };

  const saveExpense = (event: FormEvent) => {
    event.preventDefault();
    const value = Number(amount);
    if (!value) return;
    setTransactions(list => [{ id: Date.now(), merchant: name || "New expense", category, time: "Just now", day: "Today", amount: value, featured: true }, ...list]);
    setName(""); setAmount(""); setShowAdd(false); notify("Expense added");
  };

  const go = (next: View) => { setView(next); setAccount(false); };

  return (
    <main className="site-shell">
      <section className="app-window">
        <header className="window-bar"><span className="traffic red" /><span className="traffic amber" /><span className="traffic green" /><strong>Dimo — Expenses</strong></header>
        <div className="app-layout">
          <aside className="sidebar">
            <div className="brand"><span className="brand-mark">D</span><span><strong>Dimo</strong><small>Personal spending</small></span></div>
            <p className="eyebrow">Menu</p>
            <nav aria-label="Primary navigation">
              {navItems.map(item => <button key={item.id} className={view === item.id && !account ? "selected" : ""} onClick={() => go(item.id)}><Icon active={view === item.id && !account}>{item.icon}</Icon><span>{item.label}</span></button>)}
            </nav>
            <button className="primary add-side" onClick={() => setShowAdd(true)}><span>＋</span>Add expense</button>
            <div className="sidebar-spacer" />
            <div className="budget-mini"><small>Budget left in July</small><strong>{money(budgetLeft)}</strong></div>
            <button className={`profile-row ${account ? "selected" : ""}`} onClick={() => setAccount(true)}><span className="avatar">S</span><span><strong>Saiteja Segu</strong><small>Account settings</small></span><b>›</b></button>
          </aside>

          <div className="mobile-frame">
            <div className="status-bar"><strong>9:41</strong><span className="dynamic-island" /><span>5G ▰</span></div>
            <header className="mobile-header"><span><small>Good morning</small><strong>Saiteja Segu</strong></span><button className="avatar" onClick={() => setAccount(true)}>S</button></header>
            <div className="content-scroll">
              {account ? <Account onBack={() => setAccount(false)} notify={notify} /> : <>
                {view === "home" && <Overview totalSpent={totalSpent} budgetLeft={budgetLeft} recurringTotal={recurringTotal} transactions={transactions} recurring={recurring} categoryTotals={categoryTotals} go={go} open={setDetail} />}
                {view === "activity" && <Activity query={query} setQuery={setQuery} filter={filter} setFilter={setFilter} categories={categories} transactions={filtered} open={setDetail} />}
                {view === "stats" && <Stats totalSpent={totalSpent} range={range} setRange={setRange} categoryTotals={categoryTotals} transactions={transactions} />}
                {view === "recurring" && <RecurringView items={recurring} total={recurringTotal} toggle={toggleRecurring} notify={notify} />}
                {view === "budgets" && <Budgets items={categoryTotals} totalSpent={totalSpent} totalLimit={totalLimit} notify={notify} />}
              </>}
            </div>

            {!account && <button className="fab" aria-label="Add expense" onClick={() => setShowAdd(true)}>＋</button>}
            {!account && <nav className="bottom-nav" aria-label="Mobile navigation">
              {navItems.map(item => <button key={item.id} className={view === item.id ? "selected" : ""} onClick={() => go(item.id)}><Icon active={view === item.id}>{item.icon}</Icon><span>{item.id === "home" ? "Home" : item.label}</span></button>)}
            </nav>}
          </div>
        </div>

        {detail && <div className="modal-backdrop" role="presentation" onMouseDown={() => setDetail(null)}><div className="modal detail-modal" role="dialog" aria-modal="true" aria-labelledby="detail-title" onMouseDown={e => e.stopPropagation()}><div className="modal-grabber" /><MerchantMark featured={detail.featured} /><small>Expense</small><h2 id="detail-title">{detail.merchant}</h2><strong className="detail-amount">−{money(detail.amount)}</strong><dl><div><dt>Category</dt><dd>{detail.category}</dd></div><div><dt>Date</dt><dd>{detail.day}</dd></div><div><dt>Time</dt><dd>{detail.time}</dd></div></dl><div className="modal-actions"><button className="secondary" onClick={() => setDetail(null)}>Close</button><button className="danger" onClick={() => { setTransactions(list => list.filter(t => t.id !== detail.id)); setDetail(null); notify("Expense deleted"); }}>Delete</button></div></div></div>}

        {showAdd && <div className="modal-backdrop" role="presentation" onMouseDown={() => setShowAdd(false)}><form className="modal add-modal" role="dialog" aria-modal="true" aria-labelledby="add-title" onSubmit={saveExpense} onMouseDown={e => e.stopPropagation()}><div className="modal-grabber" /><h2 id="add-title">Add expense</h2><label className="amount-field"><span>₹</span><input autoFocus inputMode="decimal" value={amount} onChange={e => setAmount(e.target.value.replace(/[^0-9.]/g, ""))} placeholder="0" aria-label="Amount" /></label><label><span className="field-label">Merchant</span><input value={name} onChange={e => setName(e.target.value)} placeholder="e.g. Chai Point" /></label><fieldset><legend>Category</legend><div className="chip-row">{categories.slice(1).map(item => <button type="button" key={item} className={`chip ${category === item ? "selected" : ""}`} onClick={() => setCategory(item)}>{item}</button>)}</div></fieldset><div className="modal-actions"><button type="button" className="secondary" onClick={() => setShowAdd(false)}>Cancel</button><button className="primary" disabled={!Number(amount)}>Save expense</button></div></form></div>}
        {toast && <div className="toast" role="status">✓ {toast}</div>}
      </section>
    </main>
  );
}

function PageHeader({ eyebrow, title, aside }: { eyebrow?: string; title: string; aside?: ReactNode }) {
  return <header className="page-header"><span>{eyebrow && <small>{eyebrow}</small>}<h1>{title}</h1></span>{aside}</header>;
}

function Overview({ totalSpent, budgetLeft, recurringTotal, transactions, recurring, categoryTotals, go, open }: { totalSpent: number; budgetLeft: number; recurringTotal: number; transactions: Transaction[]; recurring: Recurring[]; categoryTotals: { name: string; spent: number; limit: number }[]; go: (v: View) => void; open: (t: Transaction) => void }) {
  return <div className="page overview-page"><PageHeader eyebrow="Good morning, Saiteja" title="Overview" aside={<span className="date-pill">Wednesday, July 9</span>} /><div className="stat-grid"><article className="hero-stat"><small>Spent in July</small><strong>{money(totalSpent)}</strong><p>{transactions.length} transactions · {money(budgetLeft)} of budget left</p></article><button className="stat-card" onClick={() => go("recurring")}><small>Recurring / mo</small><strong>{money(recurringTotal)}</strong><span>{recurring.filter(r => !r.paused).length} active bills</span></button><button className="stat-card accent" onClick={() => go("budgets")}><small>Budget left</small><strong>{money(budgetLeft)}</strong><span>{Math.round(totalSpent / 20500 * 100)}% used</span></button></div><div className="dashboard-grid"><article className="panel recent-panel"><SectionHeading title="Recent transactions" action="View all" onAction={() => go("activity")} />{transactions.slice(0, 6).map(t => <TransactionRow key={t.id} item={t} onOpen={() => open(t)} />)}</article><div className="side-stack"><article className="panel"><SectionHeading title="Upcoming" action="See all" onAction={() => go("recurring")} />{recurring.filter(r => !r.paused).slice(0, 4).map(r => <RecurringRow key={r.id} item={r} compact onToggle={() => go("recurring")} />)}</article><article className="panel categories-panel"><SectionHeading title="Top categories" />{categoryTotals.slice(0, 4).map((c, i) => <div className="progress-item" key={c.name}><span><strong>{c.name}</strong><small>{money(c.spent)} · {Math.round(c.spent / totalSpent * 100)}%</small></span><div className="progress"><i style={{ width: `${Math.max(8, c.spent / categoryTotals[0].spent * 100)}%` }} className={i ? "muted" : ""} /></div></div>)}</article></div></div></div>;
}

function Activity({ query, setQuery, filter, setFilter, categories, transactions, open }: { query: string; setQuery: (v: string) => void; filter: string; setFilter: (v: string) => void; categories: string[]; transactions: Transaction[]; open: (t: Transaction) => void }) {
  const grouped = transactions.reduce<Record<string, Transaction[]>>((all, t) => ({ ...all, [t.day]: [...(all[t.day] || []), t] }), {});
  return <div className="page"><PageHeader title="Activity" eyebrow={`${transactions.length} transactions`} aside={<label className="search"><span>⌕</span><input value={query} onChange={e => setQuery(e.target.value)} placeholder="Search merchant or category" /></label>} /><div className="chip-row filters">{categories.map(item => <button className={`chip ${filter === item ? "selected" : ""}`} onClick={() => setFilter(item)} key={item}>{item}</button>)}</div><article className="panel activity-list">{Object.keys(grouped).length ? Object.entries(grouped).map(([day, rows]) => <section className="day-group" key={day}><header><strong>{day}</strong><span>−{money(rows.reduce((sum, t) => sum + t.amount, 0))}</span></header>{rows.map(t => <TransactionRow key={t.id} item={t} onOpen={() => open(t)} />)}</section>) : <div className="empty"><span>⌕</span><h2>No expenses found</h2><p>Try another merchant or category.</p></div>}</article></div>;
}

function Stats({ totalSpent, range, setRange, categoryTotals, transactions }: { totalSpent: number; range: string; setRange: (v: string) => void; categoryTotals: { name: string; spent: number; limit: number }[]; transactions: Transaction[] }) {
  const months = [{ n: "Feb", v: 6100 }, { n: "Mar", v: 7800 }, { n: "Apr", v: 6900 }, { n: "May", v: 9200 }, { n: "Jun", v: 8400 }, { n: "Jul", v: totalSpent }];
  return <div className="page"><PageHeader title="Stats" eyebrow="Spending insights" aside={<div className="segment">{["M", "3M", "6M", "1Y"].map(r => <button key={r} className={range === r ? "selected" : ""} onClick={() => setRange(r)}>{r}</button>)}</div>} /><div className="stats-grid"><article className="panel spend-chart"><small>Spent this period</small><h2>{money(range === "M" ? totalSpent : months.reduce((s, m) => s + m.v, 0))}</h2><p><b>↓ 10.9%</b> from the previous period</p><div className="bars">{months.map(m => <div key={m.n}><span style={{ height: `${m.v / 100}%` }} className={m.n === "Jul" ? "current" : ""} /><small>{m.n}</small></div>)}</div></article><article className="panel breakdown"><SectionHeading title="By category" />{categoryTotals.map(c => <div className="progress-item" key={c.name}><span><strong>{c.name}</strong><small>{money(c.spent)}</small></span><div className="progress"><i style={{ width: `${c.spent / categoryTotals[0].spent * 100}%` }} /></div></div>)}</article><article className="panel merchants"><SectionHeading title="Top merchants" /><ol>{[...transactions].sort((a, b) => b.amount - a.amount).slice(0, 5).map((t, i) => <li key={t.id}><b>{i + 1}</b><MerchantMark featured={t.featured} /><span><strong>{t.merchant}</strong><small>{t.category}</small></span><strong>{money(t.amount)}</strong></li>)}</ol></article></div></div>;
}

function RecurringView({ items, total, toggle, notify }: { items: Recurring[]; total: number; toggle: (id: number) => void; notify: (s: string) => void }) {
  return <div className="page"><PageHeader title="Recurring" eyebrow="Bills and subscriptions" aside={<button className="primary header-action" onClick={() => notify("New recurring form ready")}>＋ Add recurring</button>} /><article className="recurring-summary"><span><small>Monthly total</small><strong>{money(total)}</strong></span><span><small>Active</small><strong>{items.filter(i => !i.paused).length}</strong></span><span><small>Paused</small><strong>{items.filter(i => i.paused).length}</strong></span></article><div className="recurring-list">{items.map(item => <RecurringRow key={item.id} item={item} onToggle={() => toggle(item.id)} />)}</div></div>;
}

function Budgets({ items, totalSpent, totalLimit, notify }: { items: { name: string; spent: number; limit: number }[]; totalSpent: number; totalLimit: number; notify: (s: string) => void }) {
  return <div className="page"><PageHeader title="Budgets" eyebrow="July 2026" aside={<button className="primary header-action" onClick={() => notify("Category form ready")}>＋ New category</button>} /><article className="budget-overview"><span><small>Total budget</small><strong>{money(totalLimit)}</strong></span><div><small>{money(totalSpent)} spent</small><small>{money(totalLimit - totalSpent)} left</small><div className="progress"><i style={{ width: `${totalSpent / totalLimit * 100}%` }} /></div></div></article><div className="budget-grid">{items.map(item => { const pct = Math.round(item.spent / item.limit * 100); return <article className="panel budget-card" key={item.name}><header><MerchantMark /><span><h2>{item.name}</h2><small>{money(item.spent)} of {money(item.limit)}</small></span><b className={pct > 80 ? "warning" : ""}>{pct}%</b></header><div className="progress"><i className={pct > 80 ? "warning" : ""} style={{ width: `${Math.min(100, pct)}%` }} /></div></article>; })}</div></div>;
}

function Account({ onBack, notify }: { onBack: () => void; notify: (s: string) => void }) {
  const [alerts, setAlerts] = useState({ bills: true, budget: true, weekly: false, large: true });
  return <div className="page account-page"><PageHeader title="Account" eyebrow="Profile and preferences" aside={<button className="secondary mobile-back" onClick={onBack}>← Back</button>} /><article className="panel profile-panel"><div className="profile-top"><span className="avatar large">S</span><span><h2>Saiteja Segu</h2><button className="text-button" onClick={() => notify("Photo picker opened")}>Change photo</button></span></div><div className="form-grid"><label><span className="field-label">Full name</span><input defaultValue="Saiteja Segu" /></label><label><span className="field-label">Email</span><input defaultValue="saiteja@example.com" type="email" /></label><button className="primary" onClick={() => notify("Profile saved")}>Save changes</button></div></article><div className="account-grid"><article className="panel"><SectionHeading title="Preferences" /><Preference title="Currency" options={["INR", "USD", "EUR"]} /><Preference title="Week starts on" options={["Mon", "Sun"]} /><Preference title="Default view" options={["Overview", "Activity", "Stats"]} /></article><article className="panel"><SectionHeading title="Notifications" />{[{ key: "bills", label: "Bill reminders", sub: "Before a recurring payment" }, { key: "budget", label: "Budget alerts", sub: "When you reach 80%" }, { key: "weekly", label: "Weekly summary", sub: "Every Monday morning" }, { key: "large", label: "Large expenses", sub: "For spends above ₹5,000" }].map(item => <div className="toggle-row" key={item.key}><span><strong>{item.label}</strong><small>{item.sub}</small></span><button role="switch" aria-checked={alerts[item.key as keyof typeof alerts]} className={`switch ${alerts[item.key as keyof typeof alerts] ? "on" : ""}`} onClick={() => setAlerts(a => ({ ...a, [item.key]: !a[item.key as keyof typeof alerts] }))}><span /></button></div>)}</article></div><div className="danger-zone"><button className="secondary" onClick={() => notify("Signed out")}>Sign out</button><button className="danger" onClick={() => notify("Delete confirmation opened")}>Delete account</button></div></div>;
}

function Preference({ title, options }: { title: string; options: string[] }) {
  const [selected, setSelected] = useState(options[0]);
  return <div className="preference"><small>{title}</small><div className="segment">{options.map(o => <button key={o} className={selected === o ? "selected" : ""} onClick={() => setSelected(o)}>{o}</button>)}</div></div>;
}

export default function Home() { return <Dashboard />; }
