const productsData = [
  { id: 1, name: "Amlodipine + Losartan",  price: 28.50, sameDay: true,  requiresRx: true,  supplierVerified: true, img: "assets/amlodipinelosartan.jpg" },
  { id: 2, name: "Amoxicillin",            price: 18.00, sameDay: false, requiresRx: true,  supplierVerified: true, img: "assets/amoxicillin.jpg"        },
  { id: 3, name: "Biogesic (Paracetamol)", price: 8.00,  sameDay: true,  requiresRx: false, supplierVerified: true, img: "assets/biogesic.jpg"            },
  { id: 4, name: "Caltrate Advance",       price: 52.00, sameDay: true,  requiresRx: false, supplierVerified: true, img: "assets/caltrateadvance.jpg"   },
  { id: 5, name: "Ibuprofen",              price: 12.00, sameDay: true,  requiresRx: false, supplierVerified: true, img: "assets/ibuprofen.jpg"          },
  { id: 6, name: "Impodex",               price: 35.00, sameDay: true,  requiresRx: false, supplierVerified: true, img: "assets/impodex.jpg"             },
];

const state = {
  prescription: null,
  verificationState: "none",
  cart: [],
  refills: [
    { id: 101, name: "Metformin 500mg", lastRefill: "2026-02-26", price: 12.00 },
  ],
};

/* ── BOOT ─────────────────────────────────────────────────── */

document.addEventListener("DOMContentLoaded", () => {
  const yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = "\u00A9 " + new Date().getFullYear();

  if (document.getElementById("products"))     setupProducts(productsData);
  if (document.getElementById("site-search"))  setupSearch();
  if (document.getElementById("rx-file"))      setupUpload();
  if (document.getElementById("quick-refill")) setupQuickRefill();
  if (document.getElementById("chat-send"))    setupChat();
  if (document.getElementById("refills"))      renderRefills();

  if (document.getElementById("cart-count")) {
    createCartDrawer();
    updateCartUI();
    const cartBtn = document.getElementById("cart-btn");
    if (cartBtn) cartBtn.addEventListener("click", openCart);
  }

  if (document.getElementById("filter-sameday")) {
    document.getElementById("filter-sameday")
      .addEventListener("change", () => setupProducts(productsData));
  }

  const viewLicenseBtn = document.getElementById("view-license");
  if (viewLicenseBtn) {
    viewLicenseBtn.addEventListener("click", () =>
      showToast("License No: PH-123456 \u2014 Department of Health, Philippines")
    );
  }

  initNav();
});

/* ── TOAST ────────────────────────────────────────────────── */

function showToast(msg, duration = 3000) {
  const t = document.getElementById("toast");
  if (!t) return;
  t.textContent = msg;
  t.classList.add("show");
  setTimeout(() => t.classList.remove("show"), duration);
}

/* ── PRESCRIPTION UPLOAD ──────────────────────────────────── */

function setupUpload() {
  const rxFile       = document.getElementById("rx-file");
  const uploadPrompt = document.getElementById("upload-prompt");
  const preview      = document.getElementById("upload-preview");
  const previewImg   = document.getElementById("preview-img");
  const previewName  = document.getElementById("preview-name");
  const previewTime  = document.getElementById("preview-time");
  const requestBtn   = document.getElementById("request-verification");
  const viewOcrBtn   = document.getElementById("view-ocr-btn");

  rxFile.addEventListener("change", (ev) => {
    const f = ev.target.files && ev.target.files[0];
    if (!f) return;
    if (f.type.startsWith("image/")) {
      const reader = new FileReader();
      reader.onload = (e) => { previewImg.src = e.target.result; };
      reader.readAsDataURL(f);
    } else {
      previewImg.src = "https://placehold.co/80x64/fde8eb/c0152a?text=PDF";
    }
    previewImg.alt          = f.name;
    previewName.textContent = f.name;
    previewTime.textContent = "Uploaded " + new Date().toLocaleString("en-PH");
    uploadPrompt.style.display = "none";
    preview.style.display      = "flex";
    const parsed = simulateOCR(f.name);
    state.prescription = { filename: f.name, parsed, uploadedAt: new Date().toISOString() };
    setVerificationState("uploaded");
  });

  requestBtn.addEventListener("click", async () => {
  if (!state.prescription) { showToast("Please upload a prescription first."); return; }

  const rxFile = document.getElementById("rx-file");
  const file   = rxFile.files && rxFile.files[0];
  if (!file) { showToast("Please upload a prescription file."); return; }

  requestBtn.disabled    = true;
  requestBtn.textContent = "Requesting…";

  try {
    const formData = new FormData();
    formData.append("file", file);
    formData.append("branch", state.selectedBranch || "punturin");

    const token = Auth.getSession ? Auth.getSession()?.access_token : null;
    const headers = {};
    if (token) headers["Authorization"] = `Bearer ${token}`;

    const res  = await fetch("/api/prescriptions/upload", {
      method:  "POST",
      headers,
      body:    formData,
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || "Upload failed.");

    setVerificationState("uploaded");
    showToast("✓ Prescription submitted! Awaiting pharmacist verification.");
  } catch (err) {
    showToast("⚠ " + err.message);
  } finally {
    requestBtn.textContent = "Request Verification";
    requestBtn.disabled    = false;
  }
});
  viewOcrBtn.addEventListener("click", () => {
    if (!state.prescription) { showToast("No OCR result available."); return; }
    const p = state.prescription.parsed;
    alert(
      "OCR Result (simulated):\n\nMedicine: " + p.medicine +
      "\nNote: " + p.note +
      "\n\nIn production, replace with Tesseract.js or a server-side OCR service."
    );
  });
}

function simulateOCR(filename) {
  const name = filename.toLowerCase();
  for (const p of productsData) {
    if (name.includes(p.name.split(" ")[0].toLowerCase()))
      return { medicine: p.name, note: "Matched by filename heuristic" };
  }
  const pick = productsData[Math.floor(Math.random() * productsData.length)];
  return { medicine: pick.name, note: "Fallback simulated match" };
}

function setVerificationState(s) {
  state.verificationState = s;
  const order = ["uploaded", "verified", "dispensed"];
  const idx   = order.indexOf(s);
  order.forEach((st, i) => {
    const li  = document.getElementById("st-" + st);
    const dot = document.getElementById("dot-" + st);
    if (!li) return;
    if (i <= idx) { li.style.opacity = "1";   if (dot) dot.classList.add("lit");    }
    else          { li.style.opacity = "0.4"; if (dot) dot.classList.remove("lit"); }
  });
}

/* ── PRODUCTS ─────────────────────────────────────────────── */

function setupProducts(data) {
  const productsEl = document.getElementById("products");
  if (!productsEl) return;
  productsEl.innerHTML = "";

  // Safe null checks — these elements only exist on index.html
  const searchEl    = document.getElementById("site-search");
  const filterEl    = document.getElementById("filter-sameday");
  const query       = searchEl ? (searchEl.value || "").trim().toLowerCase() : "";
  const sameDayOnly = filterEl ? filterEl.checked : false;

  const filtered = data.filter((p) => {
    if (sameDayOnly && !p.sameDay) return false;
    if (!query) return true;
    return p.name.toLowerCase().includes(query);
  });

  const counter = document.getElementById("results-counter");
  if (counter)
    counter.textContent = filtered.length + " item" + (filtered.length !== 1 ? "s" : "") + " found";

  if (filtered.length === 0) {
    productsEl.innerHTML =
      '<div style="grid-column:1/-1;text-align:center;padding:32px;color:var(--muted);font-size:14px;">' +
      'No medicines found. Try a different search term.</div>';
    return;
  }

  filtered.forEach((p) => {
    const node = document.createElement("div");
    node.className = "product";
    node.setAttribute("role", "listitem");

    const rxTag    = p.requiresRx
      ? '<span class="tag">Rx</span>'
      : '<span class="tag otc">OTC</span>';
    const dayTag   = p.sameDay
      ? '<span class="tag">Same-day</span>'
      : '<span class="tag days">Next day</span>';
    const thirdTag = !p.supplierVerified
      ? '<span class="tag third">Third-party</span>'
      : "";

    node.innerHTML =
      '<img alt="' + escapeHtml(p.name) + '" src="' + p.img + '" loading="lazy">' +
      '<div class="meta">' +
        '<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px;">' +
          '<div style="font-weight:700;font-size:14px;line-height:1.3;">' + escapeHtml(p.name) + '</div>' +
          '<div style="text-align:right;flex-shrink:0;">' +
            '<div style="font-weight:700;color:var(--red);">\u20B1' + p.price.toFixed(2) + '</div>' +
            '<div class="muted" style="font-size:11px;">incl. taxes</div>' +
          '</div>' +
        '</div>' +
        '<div class="tags">' + dayTag + rxTag + thirdTag + '</div>' +
        '<div style="margin-top:10px;display:flex;gap:8px;">' +
          '<button class="btn" style="font-size:12px;padding:7px 12px;" data-add="' + p.id + '">+ Add to Cart</button>' +
          '<button class="btn-ghost" style="font-size:12px;padding:7px 12px;" data-sub="' + p.id + '">Substitutes</button>' +
        '</div>' +
      '</div>';

    productsEl.appendChild(node);
  });

  productsEl.querySelectorAll("[data-add]").forEach((btn) => {
    btn.addEventListener("click", (ev) => {
      const id    = Number(ev.currentTarget.getAttribute("data-add"));
      const found = productsData.find((x) => x.id === id);
      if (found) addToCart(found);
    });
  });

  productsEl.querySelectorAll("[data-sub]").forEach((btn) => {
    btn.addEventListener("click", (ev) => {
      const id    = Number(ev.currentTarget.getAttribute("data-sub"));
      const found = productsData.find((x) => x.id === id);
      showToast("Generic substitutes for " + (found ? found.name : "this product") + " will be shown here.");
    });
  });
}

function setupSearch() {
  const searchEl = document.getElementById("site-search");
  if (!searchEl) return;
  let timeout = null;
  searchEl.addEventListener("input", () => {
    clearTimeout(timeout);
    timeout = setTimeout(() => setupProducts(productsData), 220);
  });
}

/* ── CART STATE ───────────────────────────────────────────── */

function addToCart(product) {
  const existing = state.cart.find((item) => item.id === product.id);
  if (existing) {
    existing.qty++;
  } else {
    state.cart.push({ ...product, qty: 1 });
  }
  updateCartUI();
  showToast("\u2713 " + product.name + " added to cart.");
  const btn = document.getElementById("cart-btn");
  if (btn) btn.animate(
    [{ transform: "scale(1)" }, { transform: "scale(1.06)" }, { transform: "scale(1)" }],
    { duration: 220 }
  );
}

function updateCartUI() {
  const el = document.getElementById("cart-count");
  if (el) el.textContent = state.cart.reduce((sum, item) => sum + item.qty, 0);
}

/* ── CART DRAWER ──────────────────────────────────────────── */

function createCartDrawer() {
  if (document.getElementById("cart-drawer")) return;

  // Dim overlay
  const overlay = document.createElement("div");
  overlay.id = "cart-overlay";
  overlay.style.cssText =
    "position:fixed;inset:0;background:rgba(26,5,8,0.45);z-index:1000;" +
    "opacity:0;pointer-events:none;transition:opacity 0.28s;backdrop-filter:blur(2px);";
  overlay.addEventListener("click", closeCart);

  // Drawer panel
  const drawer = document.createElement("aside");
  drawer.id = "cart-drawer";
  drawer.setAttribute("role", "dialog");
  drawer.setAttribute("aria-label", "Shopping cart");
  drawer.setAttribute("aria-modal", "true");
  drawer.style.cssText =
    "position:fixed;top:0;right:0;bottom:0;width:min(420px,100vw);" +
    "background:#fff;z-index:1001;display:flex;flex-direction:column;" +
    "box-shadow:-8px 0 40px rgba(192,21,42,0.16);" +
    "transform:translateX(100%);transition:transform 0.3s cubic-bezier(.4,0,.2,1);";

  // Header row
  const header = document.createElement("div");
  header.style.cssText =
    "display:flex;justify-content:space-between;align-items:center;" +
    "padding:18px 20px;border-bottom:1px solid var(--border);flex-shrink:0;";
  header.innerHTML =
    "<div>" +
      "<div style=\"font-family:'Playfair Display',serif;font-weight:700;font-size:1.05rem;color:var(--red);\">" +
        "&#128722; Your Cart" +
      "</div>" +
      "<div id=\"drawer-count\" style=\"font-size:12px;color:var(--muted);margin-top:1px;\"></div>" +
    "</div>" +
    "<button id=\"cart-close\" aria-label=\"Close cart\" " +
      "style=\"background:var(--red-light);border:none;border-radius:9px;width:34px;height:34px;" +
      "cursor:pointer;font-size:16px;color:var(--red);display:flex;align-items:center;justify-content:center;\">" +
      "&#x2715;" +
    "</button>";

  // Scrollable items area
  const itemsEl = document.createElement("div");
  itemsEl.id = "cart-items";
  itemsEl.style.cssText = "flex:1;overflow-y:auto;padding:16px 20px;display:none;";

  // Empty state
  const emptyEl = document.createElement("div");
  emptyEl.id = "cart-empty";
  emptyEl.style.cssText =
    "flex:1;display:flex;flex-direction:column;align-items:center;" +
    "justify-content:center;padding:40px 24px;text-align:center;";
  emptyEl.innerHTML =
    "<div style=\"font-size:48px;margin-bottom:12px;\">&#128722;</div>" +
    "<div style=\"font-weight:700;font-size:15px;color:var(--text);margin-bottom:6px;\">Your cart is empty</div>" +
    "<div style=\"font-size:13px;color:var(--muted);\">Add medicines from the catalogue to get started.</div>";

  // Footer with subtotal + checkout
  const footerEl = document.createElement("div");
  footerEl.id = "cart-footer";
  footerEl.style.cssText =
    "padding:16px 20px;border-top:1px solid var(--border);background:var(--off-white);flex-shrink:0;display:none;";
  footerEl.innerHTML =
    "<div style=\"display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;\">" +
      "<span style=\"font-size:13px;color:var(--muted);\">Subtotal</span>" +
      "<span id=\"cart-subtotal\" style=\"font-weight:700;color:var(--red);font-size:16px;\"></span>" +
    "</div>" +
    "<div style=\"margin-bottom:12px;\">" +
      "<label style=\"font-size:12px;font-weight:600;color:var(--text-sub);display:block;margin-bottom:6px;\">Pick-up Branch</label>" +
      "<select id=\"cart-branch\" " +
        "style=\"width:100%;padding:9px 12px;border-radius:10px;border:1.5px solid var(--border);" +
        "font-family:inherit;font-size:13px;background:#fff;color:var(--text);\">" +
        "<option value=\"\">Select a branch\u2026</option>" +
        "<option value=\"punturin\">Punturin Branch</option>" +
        "<option value=\"malinta\">Malinta Branch</option>" +
      "</select>" +
    "</div>" +
    "<button id=\"place-order-btn\" " +
      "style=\"width:100%;padding:12px;border-radius:10px;" +
      "background:linear-gradient(135deg,var(--red),var(--red-dark));" +
      "color:white;border:none;font-family:inherit;font-size:14px;font-weight:700;cursor:pointer;" +
      "box-shadow:0 4px 14px rgba(192,21,42,0.3);\">" +
      "Place Order \u2192" +
    "</button>" +
    "<div style=\"text-align:center;margin-top:8px;font-size:11px;color:var(--muted);\">" +
      "You'll receive an SMS/email when your order is ready." +
    "</div>";

  drawer.appendChild(header);
  drawer.appendChild(itemsEl);
  drawer.appendChild(emptyEl);
  drawer.appendChild(footerEl);
  document.body.appendChild(overlay);
  document.body.appendChild(drawer);

  document.getElementById("cart-close").addEventListener("click", closeCart);
  document.getElementById("place-order-btn").addEventListener("click", placeOrder);
  drawer.addEventListener("keydown", (e) => { if (e.key === "Escape") closeCart(); });
}

function openCart() {
  renderCartDrawer();
  const overlay = document.getElementById("cart-overlay");
  const drawer  = document.getElementById("cart-drawer");
  if (!overlay || !drawer) return;
  overlay.style.opacity       = "1";
  overlay.style.pointerEvents = "auto";
  drawer.style.transform      = "translateX(0)";
  document.body.style.overflow = "hidden";
  const closeBtn = document.getElementById("cart-close");
  if (closeBtn) closeBtn.focus();
}

function closeCart() {
  const overlay = document.getElementById("cart-overlay");
  const drawer  = document.getElementById("cart-drawer");
  if (!overlay || !drawer) return;
  overlay.style.opacity        = "0";
  overlay.style.pointerEvents  = "none";
  drawer.style.transform       = "translateX(100%)";
  document.body.style.overflow = "";
  const cartBtn = document.getElementById("cart-btn");
  if (cartBtn) cartBtn.focus();
}

function renderCartDrawer() {
  const itemsEl    = document.getElementById("cart-items");
  const footerEl   = document.getElementById("cart-footer");
  const emptyEl    = document.getElementById("cart-empty");
  const countEl    = document.getElementById("drawer-count");
  const subtotalEl = document.getElementById("cart-subtotal");
  if (!itemsEl) return;

  const totalQty = state.cart.reduce((sum, item) => sum + item.qty, 0);
  if (countEl) countEl.textContent = totalQty + " item" + (totalQty !== 1 ? "s" : "");

  if (totalQty === 0) {
    itemsEl.innerHTML      = "";
    itemsEl.style.display  = "none";
    if (emptyEl)  emptyEl.style.display  = "flex";
    if (footerEl) footerEl.style.display = "none";
    return;
  }

  if (emptyEl)  emptyEl.style.display  = "none";
  if (footerEl) footerEl.style.display = "block";
  itemsEl.style.display = "block";
  itemsEl.innerHTML = "";

  let total = 0;

  state.cart.forEach((p) => {
    total += p.price * p.qty;

    const rxBadge = p.requiresRx
      ? "<span style=\"font-size:11px;padding:2px 7px;border-radius:99px;background:var(--red-light);color:var(--red);font-weight:600;\">Rx</span>"
      : "<span style=\"font-size:11px;padding:2px 7px;border-radius:99px;background:#e8f5e9;color:#2e7d32;font-weight:600;\">OTC</span>";
    const dayBadge = p.sameDay
      ? "<span style=\"font-size:11px;padding:2px 7px;border-radius:99px;background:#f3f4f6;color:#374151;font-weight:600;\">Same-day</span>"
      : "";
    const imgSrc = p.img || "https://placehold.co/64x52/fde8eb/c0152a?text=Rx";

    const el = document.createElement("div");
    el.style.cssText =
      "display:flex;gap:12px;align-items:flex-start;" +
      "padding:12px 0;border-bottom:1px solid var(--border);";
    el.innerHTML =
      "<img src=\"" + imgSrc + "\" alt=\"" + escapeHtml(p.name) + "\" " +
        "style=\"width:64px;height:52px;object-fit:cover;border-radius:9px;" +
        "border:1px solid var(--border);flex-shrink:0;\" />" +
      "<div style=\"flex:1;min-width:0;\">" +
        "<div style=\"font-weight:700;font-size:13px;line-height:1.3;color:var(--text);\">" + escapeHtml(p.name) + "</div>" +
        "<div style=\"margin-top:4px;display:flex;gap:6px;flex-wrap:wrap;\">" + rxBadge + dayBadge + "</div>" +
        "<div style=\"display:flex;align-items:center;gap:10px;margin-top:8px;\">" +
          // qty controls
          "<div style=\"display:flex;align-items:center;gap:6px;background:var(--off-white);border:1.5px solid var(--border);border-radius:8px;padding:3px 6px;\">" +
            "<button data-dec=\"" + p.id + "\" aria-label=\"Decrease quantity\" " +
              "style=\"background:none;border:none;cursor:pointer;font-size:16px;font-weight:700;" +
              "color:var(--red);width:22px;height:22px;display:flex;align-items:center;justify-content:center;" +
              "border-radius:5px;padding:0;line-height:1;\">&#8722;</button>" +
            "<span data-qty-label=\"" + p.id + "\" style=\"font-weight:700;font-size:13px;min-width:18px;text-align:center;\">" + p.qty + "</span>" +
            "<button data-inc=\"" + p.id + "\" aria-label=\"Increase quantity\" " +
              "style=\"background:none;border:none;cursor:pointer;font-size:16px;font-weight:700;" +
              "color:var(--red);width:22px;height:22px;display:flex;align-items:center;justify-content:center;" +
              "border-radius:5px;padding:0;line-height:1;\">&#43;</button>" +
          "</div>" +
          "<div style=\"font-weight:700;color:var(--red);font-size:13px;\">\u20B1" + (p.price * p.qty).toFixed(2) + "</div>" +
        "</div>" +
      "</div>" +
      "<button data-remove=\"" + p.id + "\" aria-label=\"Remove " + escapeHtml(p.name) + "\" " +
        "style=\"background:none;border:none;cursor:pointer;font-size:18px;" +
        "color:var(--muted);padding:2px 6px;border-radius:6px;flex-shrink:0;\">&#x2715;</button>";

    // qty decrease
    el.querySelector("[data-dec]").addEventListener("click", () => {
      const item = state.cart.find((x) => x.id === p.id);
      if (!item) return;
      if (item.qty > 1) {
        item.qty--;
      } else {
        state.cart.splice(state.cart.indexOf(item), 1);
      }
      updateCartUI();
      renderCartDrawer();
    });

    // qty increase
    el.querySelector("[data-inc]").addEventListener("click", () => {
      const item = state.cart.find((x) => x.id === p.id);
      if (item) { item.qty++; updateCartUI(); renderCartDrawer(); }
    });

    // remove entirely
    el.querySelector("[data-remove]").addEventListener("click", () => {
      const idx = state.cart.findIndex((x) => x.id === p.id);
      if (idx !== -1) state.cart.splice(idx, 1);
      updateCartUI();
      renderCartDrawer();
    });

    itemsEl.appendChild(el);
  });

  if (subtotalEl) subtotalEl.textContent = "\u20B1" + total.toFixed(2);
}

async function placeOrder() {
  const branchEl = document.getElementById("cart-branch");
  const branch   = branchEl ? branchEl.value : "";
  console.log("Branch value:", JSON.stringify(branch));
  console.log("Branch map result:", branchMap[branch]);
  if (!branch) { showToast("Please select a pick-up branch."); return; }

  if (!state.cart.length) { showToast("Your cart is empty."); return; }

  const btn = document.getElementById("place-order-btn");
  if (btn) { btn.textContent = "Placing order…"; btn.disabled = true; }

  try {
    const branchMap = {
  punturin: "12a814e2-f9b9-42a7-87a1-f5a66bfc5904",
  malinta:  "850afc97-c7d3-4cc9-b119-deedb07fd1ac"
};

const res = await Auth.fetch('/orders', {
  method:  'POST',
  headers: { 'Content-Type': 'application/json' },
  body:    JSON.stringify({
    branch_id: branchMap[branch] || branch,
    items: state.cart.map(i => ({
      medicine_id: i.id,
      quantity:    i.qty,
      unit_price:  i.price,
    })),
  }),
});
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Order failed.');

    const branchName = branch === "punturin" ? "Punturin" : "Malinta";
    state.cart = [];
    updateCartUI();
    closeCart();
    showToast("✓ Order placed! Ready for pick-up at " + branchName + " Branch.", 4500);
  } catch (err) {
    showToast("⚠ " + err.message);
  } finally {
    if (btn) { btn.textContent = "Place Order →"; btn.disabled = false; }
  }
}
/* ── QUICK REFILL ─────────────────────────────────────────── */

function setupQuickRefill() {
  document.getElementById("quick-refill").addEventListener("click", () => {
    const refill = {
      id: 99, name: "Metformin 500mg (Refill)", price: 12.00,
      sameDay: true, requiresRx: true,
      img: "https://placehold.co/80x64/fde8eb/c0152a?text=Metformin",
    };
    addToCart(refill);
    showToast("\u26A1 Quick refill added to cart \u2014 proceed to pick-up.");
  });
}

/* ── REFILL REMINDERS ─────────────────────────────────────── */

function renderRefills() {
  const el = document.getElementById("refills");
  if (!el) return;
  el.innerHTML = "";

  if (state.refills.length === 0) {
    el.innerHTML = '<div class="muted" style="padding:14px;text-align:center;font-size:13px;">No refill reminders set up yet.</div>';
    return;
  }

  state.refills.forEach((r) => {
    const item = document.createElement("div");
    item.className = "refill-item";
    item.innerHTML =
      "<div>" +
        "<div style=\"font-weight:700;font-size:14px;\">" + escapeHtml(r.name) + "</div>" +
        "<div class=\"muted\" style=\"margin-top:2px;\">Last refill: " + escapeHtml(r.lastRefill) +
        " &nbsp;&middot;&nbsp; \u20B1" + r.price.toFixed(2) + "</div>" +
      "</div>" +
      "<div style=\"display:flex;gap:8px;flex-shrink:0;\">" +
        "<button class=\"btn\" style=\"font-size:12px;padding:7px 12px;\" data-refill=\"" + r.id + "\">Refill Now</button>" +
        "<button class=\"btn-ghost\" style=\"font-size:12px;padding:7px 12px;\" data-sched=\"" + r.id + "\">Schedule</button>" +
      "</div>";
    el.appendChild(item);
  });

  el.querySelectorAll("[data-refill]").forEach((btn) => {
    btn.addEventListener("click", (ev) => {
      const id    = Number(ev.currentTarget.getAttribute("data-refill"));
      const found = state.refills.find((x) => x.id === id);
      if (!found) return;
      addToCart({
        id: 200, name: found.name + " (Refill)", price: found.price,
        sameDay: true, requiresRx: true,
        img: "https://placehold.co/80x64/fde8eb/c0152a?text=Refill",
      });
    });
  });

  el.querySelectorAll("[data-sched]").forEach((btn) => {
    btn.addEventListener("click", () => showToast("Refill scheduling coming soon."));
  });
}

/* ── PHARMACIST CHAT ──────────────────────────────────────── */

function setupChat() {
  const send  = document.getElementById("chat-send");
  const input = document.getElementById("chat-input");
  if (!send || !input) return;

  send.addEventListener("click", () => {
    const text = input.value && input.value.trim();
    if (!text) return;
    appendChat("You", text, true);
    input.value   = "";
    send.disabled = true;
    setTimeout(() => {
      appendChat("Pharmacist", generatePharmacistReply(text), false);
      send.disabled = false;
    }, 900);
  });

  input.addEventListener("keypress", (e) => {
    if (e.key === "Enter") { send.click(); e.preventDefault(); }
  });
}

function appendChat(who, text, isUser) {
  const box = document.getElementById("chat-box");
  if (!box) return;
  const m = document.createElement("div");
  m.className = "chat-msg";
  m.innerHTML =
    "<div class=\"who " + (isUser ? "" : "them") + "\">" + escapeHtml(who) + "</div>" +
    "<div class=\"body\">" + escapeHtml(text) + "</div>";
  box.appendChild(m);
  box.scrollTop = box.scrollHeight;
}

function generatePharmacistReply(text) {
  const t = text.toLowerCase();
  if (t.includes("interaction") || t.includes("safe with") || t.includes("combine"))
    return "Please list all the medicines you're currently taking and I'll check for interactions. This is informational \u2014 always confirm with your doctor.";
  if (t.includes("metformin"))
    return "Metformin is generally well-tolerated. Avoid combining with certain antivirals. Share your full medication list and I can check for you.";
  if (t.includes("paracetamol") || t.includes("biogesic"))
    return "Paracetamol is safe for most people at recommended doses (500mg every 4\u20136 hours). Do not exceed 4g per day. Avoid alcohol.";
  if (t.includes("refill") || t.includes("repeat"))
    return "You can set up a refill reminder through your account, or just click \u2018Refill Now\u2019 on your last order. Want me to help?";
  if (t.includes("delivery") || t.includes("pick") || t.includes("collect"))
    return "We currently offer Click & Collect at our Punturin and Malinta branches. Select your branch when checking out.";
  if (t.includes("prescription") || t.includes("rx") || t.includes("upload"))
    return "Upload a photo or PDF of your prescription using the upload box. I'll review it personally before your order is prepared.";
  if (t.includes("gcash") || t.includes("maya") || t.includes("payment"))
    return "We accept GCash, Maya, debit/credit cards, and cash payment in-store. Choose your payment method at checkout.";
  return "Thank you for your question! I can help with dosage, interactions, or prescription queries. For urgent concerns, please visit our branch directly.";
}

/* ── NAV ──────────────────────────────────────────────────── */

function initNav() {
  const toggle = document.querySelector(".nav-toggle");
  const menu   = document.getElementById("nav-menu");
  if (!toggle || !menu) return;

  toggle.addEventListener("click", () => {
    const expanded = toggle.getAttribute("aria-expanded") === "true";
    toggle.setAttribute("aria-expanded", String(!expanded));
    menu.hidden = expanded;
    if (!menu.hidden) menu.querySelector("a")?.focus();
  });

  document.addEventListener("click", (e) => {
    if (menu.hidden) return;
    if (!menu.contains(e.target) && !toggle.contains(e.target)) {
      menu.hidden = true;
      toggle.setAttribute("aria-expanded", "false");
    }
  });

  const links   = menu.querySelectorAll("a");
  const current = (location.pathname.split("/").pop() || "index.html").toLowerCase();
  links.forEach((a) => {
    const href = (a.getAttribute("href") || "").split("/").pop().toLowerCase();
    if (href === current || (href === "index.html" && current === ""))
      a.classList.add("active");
    else
      a.classList.remove("active");
  });
}

/* ── UTILS ────────────────────────────────────────────────── */

function escapeHtml(s) {
  if (s == null) return "";
  return String(s)
    .replaceAll("&",  "&amp;")
    .replaceAll("<",  "&lt;")
    .replaceAll(">",  "&gt;")
    .replaceAll('"',  "&quot;")
    .replaceAll("'",  "&#039;");
}

window._addToCart = function(btn) {
  const product = {
    id:         btn.dataset.id,
    name:       btn.dataset.name,
    price:      parseFloat(btn.dataset.price),
    requiresRx: btn.dataset.rx === 'true'
  };
  addToCart(product);
};
