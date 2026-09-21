// Global Top-Level Navigation Helper to guarantee Home Page Redirection
window.navigateToHomeScreen = function() {
  if (typeof window.navigateToScreenRef === 'function') {
    window.navigateToScreenRef('home-tab');
  } else {
    const authContainer = document.getElementById('auth-flow-container');
    const mainAppHeader = document.getElementById('mainAppHeader');
    const mainBottomNav = document.getElementById('mainBottomNav');
    const appTabs = document.querySelectorAll('.tab-content');
    
    if (authContainer) authContainer.style.display = 'none';
    if (mainAppHeader) mainAppHeader.style.display = 'flex';
    if (mainBottomNav) mainBottomNav.style.display = 'block';

    appTabs.forEach(t => t.style.display = 'none');
    const homeTab = document.getElementById('home-tab');
    if (homeTab) homeTab.style.display = 'block';

    document.querySelectorAll('.bottom-nav .nav-item').forEach(item => {
      item.classList.remove('active');
      if (item.getAttribute('data-tab') === 'home-tab') {
        item.classList.add('active');
      }
    });
  }

  if (typeof window.showCategoryToastRef === 'function') {
    window.showCategoryToastRef('Redirecting to Home Page...');
  }

  const container = document.querySelector('.app-container');
  if (container) container.scrollTop = 0;
  document.querySelectorAll('.auth-flow-view, .tab-content').forEach(el => el.scrollTop = 0);
  window.scrollTo(0, 0);
};

document.addEventListener('DOMContentLoaded', () => {
  // 1. Theme Toggle
  const themeToggle = document.getElementById('themeToggle');
  if (themeToggle) {
    const themeIcon = themeToggle.querySelector('i');
    themeToggle.addEventListener('click', () => {
      document.body.classList.toggle('dark-mode');
      if (document.body.classList.contains('dark-mode')) {
        if (themeIcon) themeIcon.className = 'fas fa-sun';
      } else {
        if (themeIcon) themeIcon.className = 'fas fa-moon';
      }
    });
  }


  // 2. STATEFUL CART MANAGER
  let cartState = [];

  function updateCartUI() {
    const totalCount = cartState.reduce((sum, item) => sum + item.quantity, 0);

    const headerCartBadge = document.getElementById('headerCartBadge');
    if (headerCartBadge) {
      headerCartBadge.textContent = totalCount;
      headerCartBadge.style.display = totalCount > 0 ? 'flex' : 'none';
    }

    renderCartTabContent();
  }

  function addProductToCart(productData, targetButtonElement = null) {
    const existingIndex = cartState.findIndex(item => item.sku === productData.sku || item.name === productData.name);

    if (existingIndex > -1) {
      cartState[existingIndex].quantity += 1;
    } else {
      cartState.push({
        id: productData.sku || 'RO-' + Date.now(),
        name: productData.name,
        brand: productData.brand || 'AQUACLEAN',
        price: productData.price,
        numericPrice: parseInt((productData.price || '850').replace(/\D/g, '')),
        moq: productData.moq || 'MOQ: 1',
        imgSrc: productData.imgSrc || 'purifier.jpg',
        sku: productData.sku || 'RO-PART-2026',
        quantity: 1
      });
    }

    updateCartUI();

    if (targetButtonElement) {
      const originalHTML = targetButtonElement.innerHTML;
      targetButtonElement.classList.add('added-success');
      targetButtonElement.innerHTML = '✓ Added';
      
      setTimeout(() => {
        targetButtonElement.classList.remove('added-success');
        targetButtonElement.innerHTML = originalHTML;
      }, 1200);
    }

    showCategoryToast(`✓ Added 1x "${productData.name}" to Cart! (${getTotalCartCount()} Total Items)`);
  }

  function getTotalCartCount() {
    return cartState.reduce((sum, item) => sum + item.quantity, 0);
  }

  // Render Orders / Cart Tab List Dynamically
  function renderCartTabContent() {
    const ordersTab = document.getElementById('orders-tab');
    if (!ordersTab) return;

    if (cartState.length === 0) {
      ordersTab.innerHTML = `
        <div class="catalog-pearl-header">
          <div class="catalog-pearl-title-row">
            <div class="catalog-pearl-title-group" style="display: flex; align-items: center; gap: 10px;">
              <button class="app-top-back-btn" id="btnBackFromOrdersTab" aria-label="Go back">
                <i class="fas fa-chevron-left"></i>
              </button>
              <h3 class="catalog-pearl-title">Wholesale Cart & Orders</h3>
            </div>
          </div>
        </div>

        <div class="section-container" style="padding-top: 16px; text-align: center;">
          <div style="background-color: var(--bg-surface); padding: 40px 20px; border-radius: 20px; border: 1px solid var(--border-color); text-align: center;">
            <div style="font-size: 42px; color: var(--text-muted); margin-bottom: 12px;"><i class="fas fa-shopping-basket"></i></div>
            <h3 style="font-size: 16px; font-weight: 800; color: var(--text-charcoal); margin-bottom: 6px;">Your B2B Cart is Empty</h3>
            <p style="font-size: 12px; color: var(--text-muted); margin-bottom: 20px;">Click on any product to open details and add wholesale orders to your cart.</p>
            <button class="btn-modal-buy" id="cartBrowseBtn" style="width: auto; padding: 0 24px;">Browse Catalog</button>
          </div>
        </div>
      `;

      document.getElementById('btnBackFromOrdersTab')?.addEventListener('click', () => goBack());
      document.getElementById('cartBrowseBtn')?.addEventListener('click', () => switchTab('products-tab'));
      return;
    }

    let subtotal = cartState.reduce((sum, item) => sum + (item.numericPrice * item.quantity), 0);
    let discount = Math.round(subtotal * 0.10); // 10% Gold Dealer Discount
    let gst = Math.round((subtotal - discount) * 0.18); // 18% B2B GST Tax
    let delivery = subtotal > 5000 ? 0 : 250;
    let grandTotal = (subtotal - discount) + gst + delivery;

    let itemsHTML = cartState.map((item, idx) => `
      <div class="cart-item-row" style="display: flex; gap: 12px; padding: 14px; background: var(--bg-surface); border-radius: 16px; border: 1px solid var(--border-color); margin-bottom: 12px; align-items: center;">
        <img src="${item.imgSrc}" alt="${item.name}" style="width: 55px; height: 55px; object-fit: contain; background: var(--bg-page); border-radius: 10px; padding: 4px;">
        <div style="flex: 1;">
          <div style="font-size: 8px; font-weight: 800; color: var(--primary-blue); text-transform: uppercase;">${item.brand}</div>
          <div style="font-size: 12px; font-weight: 700; color: var(--text-charcoal); margin-bottom: 4px; line-height: 1.2;">${item.name}</div>
          <div style="font-size: 13px; font-weight: 850; color: var(--primary-blue);">₹${item.numericPrice.toLocaleString()}</div>
        </div>
        <div style="display: flex; align-items: center; gap: 8px; background: var(--bg-page); padding: 4px 8px; border-radius: 20px; border: 1px solid var(--border-color);">
          <button class="cart-qty-btn decrease-qty" data-index="${idx}" style="background: none; border: none; font-weight: 900; font-size: 14px; cursor: pointer; color: var(--text-charcoal); width: 20px;">-</button>
          <span style="font-size: 12px; font-weight: 800; width: 18px; text-align: center;">${item.quantity}</span>
          <button class="cart-qty-btn increase-qty" data-index="${idx}" style="background: none; border: none; font-weight: 900; font-size: 14px; cursor: pointer; color: var(--primary-blue); width: 20px;">+</button>
        </div>
      </div>
    `).join('');

    ordersTab.innerHTML = `
      <div class="catalog-pearl-header">
        <div class="catalog-pearl-title-row" style="display: flex; align-items: center; justify-content: space-between;">
          <div class="catalog-pearl-title-group" style="display: flex; align-items: center; gap: 10px;">
            <button class="app-top-back-btn" id="btnBackFromOrdersTab" aria-label="Go back">
              <i class="fas fa-chevron-left"></i>
            </button>
            <h3 class="catalog-pearl-title">Shopping Cart (${cartState.length})</h3>
          </div>
          <span style="font-size: 11px; font-weight: 800; color: var(--primary-blue); background: #EFF6FF; padding: 4px 10px; border-radius: 12px; border: 1px solid rgba(15, 98, 254, 0.2);">Gold Dealer</span>
        </div>
      </div>

      <div class="section-container" style="padding-top: 16px; padding-bottom: 70px;">
        <div class="cart-items-list">
          ${itemsHTML}
        </div>

        <div style="background: var(--bg-surface); padding: 16px; border-radius: 16px; border: 1px solid var(--border-color); margin-top: 16px;">
          <div style="font-size: 13px; font-weight: 800; color: var(--text-charcoal); margin-bottom: 12px;">Price Summary</div>
          <div style="display: flex; justify-content: space-between; font-size: 12px; color: var(--text-muted); margin-bottom: 6px;">
            <span>Subtotal</span>
            <span>₹${subtotal.toLocaleString()}</span>
          </div>
          <div style="display: flex; justify-content: space-between; font-size: 12px; color: #10B981; margin-bottom: 6px;">
            <span>Gold Dealer Discount (10%)</span>
            <span>-₹${discount.toLocaleString()}</span>
          </div>
          <div style="display: flex; justify-content: space-between; font-size: 12px; color: var(--text-muted); margin-bottom: 6px;">
            <span>B2B Input GST (18%)</span>
            <span>+₹${gst.toLocaleString()}</span>
          </div>
          <div style="display: flex; justify-content: space-between; font-size: 12px; color: var(--text-muted); margin-bottom: 12px;">
            <span>Express Wholesale Delivery</span>
            <span>${delivery === 0 ? 'FREE' : '₹' + delivery}</span>
          </div>
          <div style="display: flex; justify-content: space-between; font-size: 15px; font-weight: 900; color: var(--text-charcoal); border-top: 1px dashed var(--border-color); padding-top: 10px;">
            <span>Grand Total</span>
            <span style="color: var(--primary-blue);">₹${grandTotal.toLocaleString()}</span>
          </div>

          <button id="cartCheckoutBtn" class="btn-modal-buy" style="width: 100%; margin-top: 16px; height: 48px; font-size: 14px;">Proceed to B2B Checkout</button>
        </div>
      </div>
    `;

    document.getElementById('btnBackFromOrdersTab')?.addEventListener('click', () => goBack());

    document.querySelectorAll('.decrease-qty').forEach(btn => {
      btn.addEventListener('click', (e) => {
        const idx = parseInt(btn.getAttribute('data-index'));
        if (cartState[idx].quantity > 1) {
          cartState[idx].quantity -= 1;
        } else {
          cartState.splice(idx, 1);
        }
        updateCartUI();
      });
    });

    document.querySelectorAll('.increase-qty').forEach(btn => {
      btn.addEventListener('click', (e) => {
        const idx = parseInt(btn.getAttribute('data-index'));
        cartState[idx].quantity += 1;
        updateCartUI();
      });
    });

    document.getElementById('cartCheckoutBtn')?.addEventListener('click', () => {
      navigateToScreen('checkout-tab');
    });
  }

  // 3. Bottom Navigation & Tabs switching
  const navItems = document.querySelectorAll('.nav-item');
  const tabs = document.querySelectorAll('.tab-content');

  // ==========================================================================
  // 12-SCREEN ROUTER & AUTHENTICATION FLOW SYSTEM
  // ==========================================================================
  const authContainer = document.getElementById('auth-flow-container');
  const mainAppHeader = document.getElementById('mainAppHeader');
  const mainBottomNav = document.getElementById('mainBottomNav');
  const authScreens = document.querySelectorAll('.auth-flow-view');
  const appTabs = document.querySelectorAll('.tab-content');

  // Track authentication state
  let isUserAuthenticated = localStorage.getItem('ro_b2b_logged_in') === 'true';
  let registeredUserData = JSON.parse(localStorage.getItem('ro_b2b_user') || '{"business": "Sri Aqua Traders", "owner": "Karthick R"}');
  let screenHistoryStack = [];

  function goBack() {
    const openModals = document.querySelectorAll('.product-modal-overlay[style*="display: flex"]');
    if (openModals.length > 0) {
      openModals.forEach(m => m.style.display = 'none');
      document.body.style.overflow = '';
      return;
    }

    if (screenHistoryStack.length > 1) {
      screenHistoryStack.pop(); // Remove active current screen
      const previousScreen = screenHistoryStack[screenHistoryStack.length - 1];
      console.log('Navigating back to actual history screen:', previousScreen);
      navigateToScreen(previousScreen, false);
    } else {
      navigateToScreen('home-tab', false);
    }
  }
  window.goBack = goBack;

  function navigateToScreen(screenId, updateHistory = true) {
    console.log('Navigating to screen:', screenId);
    window.navigateToScreenRef = navigateToScreen;

    // Protection Guard: If attempting to access main app tab without a valid token, redirect to Login
    const token = localStorage.getItem('ro_b2b_token');
    if (!screenId.startsWith('screen-') && !token) {
      console.warn('Unauthenticated access attempt to:', screenId);
      showCategoryToast('⚠️ Please login to access the Dealer Portal.');
      screenId = 'screen-login';
    }

    if (updateHistory) {
      if (screenHistoryStack.length === 0 || screenHistoryStack[screenHistoryStack.length - 1] !== screenId) {
        screenHistoryStack.push(screenId);
      }
    }

    const appContainerElem = document.querySelector('.app-container');
    if (appContainerElem) {
      if (screenId === 'screen-splash') {
        appContainerElem.classList.remove('scrollable-view');
        appContainerElem.scrollTop = 0;
      } else {
        appContainerElem.classList.add('scrollable-view');
      }
    }

    if (screenId.startsWith('screen-')) {
      // Show Auth Flow
      if (authContainer) authContainer.style.display = 'flex';
      if (mainAppHeader) mainAppHeader.style.display = 'none';
      if (mainBottomNav) mainBottomNav.style.display = 'none';

      authScreens.forEach(s => s.style.display = 'none');
      const targetScreen = document.getElementById(screenId);
      if (targetScreen) {
        targetScreen.style.display = 'flex';
      }
      appTabs.forEach(t => t.style.display = 'none');
    } else {
      // Show Main App Flow
      if (authContainer) authContainer.style.display = 'none';
      if (mainAppHeader) mainAppHeader.style.display = 'flex';
      if (mainBottomNav) mainBottomNav.style.display = 'block';

      appTabs.forEach(t => t.style.display = 'none');
      const activeTab = document.getElementById(screenId);
      if (activeTab) activeTab.style.display = 'block';

      // Update Bottom Navigation active tab icon
      document.querySelectorAll('.bottom-nav .nav-item').forEach(item => {
        item.classList.remove('active');
        if (item.getAttribute('data-tab') === screenId) {
          item.classList.add('active');
        }
      });

      if (screenId === 'products-tab') {
        renderCatalogProducts('all');
      } else if (screenId === 'orders-tab') {
        renderCartTabContent();
      } else if (screenId === 'checkout-tab') {
        loadCheckoutAddresses();
      } else if (screenId === 'profile-tab') {
        renderUserProfileData();
      }
    }

    if (screenId === 'screen-splash') {
      triggerSplashAutoNavigate();
    } else {
      if (splashAutoTimer) clearTimeout(splashAutoTimer);
    }

    if (updateHistory) {
      history.pushState({ screen: screenId }, '', `#${screenId}`);
    }
  }

  // 1. Splash Screen Auto Navigation & Progress Bar Animation
  let splashAutoTimer = null;

  function triggerSplashAutoNavigate() {
    if (splashAutoTimer) clearTimeout(splashAutoTimer);

    const progressFill = document.getElementById('splashProgressFill');
    if (progressFill) {
      progressFill.style.transition = 'none';
      progressFill.style.width = '0%';
      setTimeout(() => {
        progressFill.style.transition = 'width 3.5s linear';
        progressFill.style.width = '100%';
      }, 50);
    }

    splashAutoTimer = setTimeout(() => {
      const splashElem = document.getElementById('screen-splash');
      if (splashElem && splashElem.style.display !== 'none') {
        navigateToScreen('screen-login');
      }
    }, 3600);
  }

  const splashScreen = document.getElementById('screen-splash');
  if (splashScreen) {
    splashScreen.addEventListener('click', () => {
      if (splashAutoTimer) clearTimeout(splashAutoTimer);
      navigateToScreen('screen-login');
    });

    // 3D Parallax Tilt Effect on Mouse/Touch Move for Splash Stage
    const splashImg = splashScreen.querySelector('.splash-3d-ro-img');
    if (splashImg) {
      splashScreen.addEventListener('mousemove', (e) => {
        const rect = splashScreen.getBoundingClientRect();
        const x = e.clientX - rect.left - rect.width / 2;
        const y = e.clientY - rect.top - rect.height / 2;
        splashImg.style.transform = `perspective(600px) rotateY(${x * 0.04}deg) rotateX(${-y * 0.04}deg) translateY(-8px) scale(1.03)`;
      });

      splashScreen.addEventListener('mouseleave', () => {
        splashImg.style.transform = `none`;
      });
    }
  }

  // Global helper exposed on window for Home Page redirection
  window.navigateToHomeScreen = function() {
    showCategoryToast('Redirecting to Home Page...');
    navigateToScreen('home-tab');
    const container = document.querySelector('.app-container');
    if (container) container.scrollTop = 0;
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  // Universal Top-Left Back & Brand Logo Navigation Handlers Across All Pages
  document.addEventListener('click', (e) => {
    // 1. Back button click -> Go to actual previous screen using navigation history stack!
    const backBtn = e.target.closest('.app-top-back-btn, .btn-auth-back');
    if (backBtn) {
      e.preventDefault();
      e.stopPropagation();
      goBack();
      return;
    }

    // 2. RO Badge click -> Open RO Category Hub Modal
    const roBadgeBtn = e.target.closest('#headerRoBadgeBtn, .logo-badge-wrapper, .logo-badge-text');
    if (roBadgeBtn) {
      e.preventDefault();
      e.stopPropagation();
      openModal('roCategoriesSubModal');
      showCategoryToast('Opening RO Product Categories & Systems Hub...');
      return;
    }

    // 3. Brand Logo / Header text click -> Go directly to Home page
    const logoHeader = e.target.closest(
      '#headerLogoBrandBtn, .logo-text-wrapper, .logo-main-text, .app-subtitle-pill'
    );
    if (logoHeader) {
      e.preventDefault();
      e.stopPropagation();
      window.navigateToHomeScreen();
      return;
    }
  });

  // ==========================================================================
  // REAL B2B AUTHENTICATION SERVICE (EMAIL OTP & GOOGLE OAUTH REST API)
  // ==========================================================================
  // ==========================================================================
  // REAL B2B AUTHENTICATION SERVICE (PASSWORD, EMAIL OTP & GOOGLE OAUTH REST API)
  // ==========================================================================
  const B2BAuthService = {
    activeSessionEmail: '',

    // Password Login Method
    loginWithPassword: async function(identifier, password) {
      const cleanId = (identifier || '').trim();
      const cleanPass = (password || '').trim();

      if (!cleanId || !cleanPass) {
        return { success: false, error: 'Please enter your email/mobile and password.' };
      }

      const loginBtn = document.getElementById('btnLoginSubmit');
      const origText = loginBtn ? loginBtn.innerHTML : '';
      if (loginBtn) {
        loginBtn.disabled = true;
        loginBtn.innerHTML = '<span>Logging in...</span> <i class="fas fa-spinner fa-spin"></i>';
      }

      try {
        const response = await fetch('/api/auth/login', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ identifier: cleanId, password: cleanPass })
        });

        const data = await response.json();

        if (loginBtn) {
          loginBtn.disabled = false;
          loginBtn.innerHTML = origText;
        }

        if (!response.ok || !data.success) {
          return { success: false, error: data.error || 'Invalid email/mobile or password.' };
        }

        // Save authenticated session
        isUserAuthenticated = true;
        localStorage.setItem('ro_b2b_logged_in', 'true');
        localStorage.setItem('ro_b2b_token', data.token);
        localStorage.setItem('ro_b2b_user', JSON.stringify(data.user));

        const profileTitle = document.getElementById('profileBusinessTitle');
        if (profileTitle && data.user) {
          profileTitle.textContent = data.user.name || data.user.owner || 'Approved Dealer';
        }

        return { success: true, user: data.user };
      } catch (err) {
        if (loginBtn) {
          loginBtn.disabled = false;
          loginBtn.innerHTML = origText;
        }
        console.error('[API ERROR] Login request failed:', err);
        return { success: false, error: 'Network error during login.' };
      }
    },

    // Sign Up Method
    submitSignUp: async function(formData) {
      const submitBtn = document.getElementById('btnSubmitReg');
      const origText = submitBtn ? submitBtn.innerHTML : '';
      if (submitBtn) {
        submitBtn.disabled = true;
        submitBtn.innerHTML = '<span>Submitting Application...</span> <i class="fas fa-spinner fa-spin"></i>';
      }

      try {
        const response = await fetch('/api/auth/signup', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(formData)
        });

        const data = await response.json();

        if (submitBtn) {
          submitBtn.disabled = false;
          submitBtn.innerHTML = origText;
        }

        if (!response.ok || !data.success) {
          return { success: false, error: data.error || 'Failed to submit application.' };
        }

        return { success: true, message: data.message };
      } catch (err) {
        if (submitBtn) {
          submitBtn.disabled = false;
          submitBtn.innerHTML = origText;
        }
        console.error('[API ERROR] Signup request failed:', err);
        return { success: false, error: 'Network error during signup.' };
      }
    },

    // Step 1: Send OTP to Email / Mobile via Backend REST API
    // Step 1: Send OTP to Email / Mobile via Backend REST API
    sendOTP: async function(targetEmailOrMobile) {
      const target = (targetEmailOrMobile || '').trim();
      const sendBtn = document.getElementById('btnSendOtpSubmit') || document.getElementById('btnSendOtp');
      const origText = sendBtn ? sendBtn.innerHTML : '';

      if (sendBtn) {
        sendBtn.disabled = true;
        sendBtn.innerHTML = '<span>Sending OTP...</span> <i class="fas fa-spinner fa-spin"></i>';
      }

      try {
        const response = await fetch('/api/auth/send-otp', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email: target })
        });

        const data = await response.json();

        if (sendBtn) {
          sendBtn.disabled = false;
          sendBtn.innerHTML = origText;
        }

        if (!response.ok || !data.success) {
          const errorMsg = data.error || 'Failed to send OTP. Please try again.';
          const errElem = document.getElementById('errOtpRequestTarget');
          const boxElem = document.getElementById('boxOtpRequestTarget');
          if (errElem) {
            errElem.textContent = errorMsg;
            errElem.style.display = 'block';
          }
          if (boxElem) boxElem.classList.add('error');
          showCategoryToast(errorMsg);
          return false;
        }

        const actualEmail = data.email || target;
        this.activeSessionEmail = actualEmail;
        sessionStorage.setItem('ro_auth_email', actualEmail);

        // Update UI Target Display
        const displayElem = document.getElementById('otpDisplayTarget');
        if (displayElem) displayElem.textContent = actualEmail;

        // Clear digit boxes
        document.querySelectorAll('.otp-digit-box').forEach(b => b.value = '');

        // Confirmation Toast ONLY shown on verified successful email dispatch
        showCategoryToast(data.otp ? `🎉 OTP sent successfully (Code: ${data.otp})` : '🎉 OTP sent successfully');

        // Log to browser console for instant developer inspection
        if (data.otp) {
          console.log(`🔑 [OTP SUCCESS] Verification Code for ${actualEmail}: ${data.otp}`);
        }

        // Navigate to OTP Verification Screen & Start Countdown Timer
        navigateToScreen('screen-otp');
        startOtpCountdownTimer();
        return true;
      } catch (err) {
        if (sendBtn) {
          sendBtn.disabled = false;
          sendBtn.innerHTML = origText;
        }
        console.error('[API ERROR] Send OTP request failed:', err);
        showCategoryToast('Failed to send OTP. Please try again.');
        return false;
      }
    },

    // Step 2: Verify OTP via Backend REST API
    verifyOTP: async function(enteredCode) {
      const email = this.activeSessionEmail || sessionStorage.getItem('ro_auth_email') || document.getElementById('loginIdentifierInput')?.value?.trim();
      if (!email) {
        return { success: false, error: '⚠️ Session expired. Please enter your email/mobile again.' };
      }

      const verifyBtn = document.getElementById('btnVerifyOtp');
      const origText = verifyBtn ? verifyBtn.innerHTML : '';
      if (verifyBtn) {
        verifyBtn.disabled = true;
        verifyBtn.innerHTML = '<span>Verifying...</span> <i class="fas fa-spinner fa-spin"></i>';
      }

      try {
        const response = await fetch('/api/auth/verify-otp', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email: email, otp: enteredCode })
        });

        const data = await response.json();

        if (verifyBtn) {
          verifyBtn.disabled = false;
          verifyBtn.innerHTML = origText;
        }

        if (!response.ok || !data.success) {
          return { success: false, error: data.error || '❌ Invalid OTP code entered.' };
        }

        // Successful OTP Verification
        isUserAuthenticated = true;
        localStorage.setItem('ro_b2b_logged_in', 'true');
        localStorage.setItem('ro_b2b_token', data.user?.token || `RO_B2B_JWT_${Date.now()}`);
        localStorage.setItem('ro_b2b_user', JSON.stringify(data.user));

        sessionStorage.removeItem('ro_auth_email');
        this.activeSessionEmail = '';

        return { success: true };
      } catch (err) {
        if (verifyBtn) {
          verifyBtn.disabled = false;
          verifyBtn.innerHTML = origText;
        }
        console.error('[API ERROR] Verify OTP request failed:', err);
        return { success: false, error: '❌ Network error during verification.' };
      }
    },

    // Resend OTP
    resendOTP: function() {
      const email = this.activeSessionEmail || sessionStorage.getItem('ro_auth_email') || document.getElementById('loginIdentifierInput')?.value?.trim();
      if (!email) {
        showCategoryToast('⚠️ Please enter your email address');
        navigateToScreen('screen-login');
        return false;
      }
      return this.sendOTP(email);
    },

    // Google Sign-In Authentication
    signInWithGoogle: async function() {
      const googleBtn = document.getElementById('btnGoogleSignIn');
      const origHTML = googleBtn ? googleBtn.innerHTML : '';

      const resetBtnState = () => {
        if (googleBtn) {
          googleBtn.disabled = false;
          googleBtn.innerHTML = origHTML;
        }
      };

      if (googleBtn) {
        googleBtn.disabled = true;
        googleBtn.innerHTML = '<i class="fab fa-google" style="color: #EA4335;"></i> <span>Signing in with Google...</span> <i class="fas fa-spinner fa-spin"></i>';
      }

      const handleCredentialOrToken = async (credentialOrToken) => {
        try {
          if (googleBtn) {
            googleBtn.innerHTML = '<i class="fab fa-google" style="color: #EA4335;"></i> <span>Signing in...</span> <i class="fas fa-spinner fa-spin"></i>';
          }

          const apiRes = await fetch('/api/auth/google-signin', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              credential: credentialOrToken.credential,
              accessToken: credentialOrToken.access_token
            })
          });

          const data = await apiRes.json();
          resetBtnState();

          if (!apiRes.ok || !data.success) {
            if (data.status === 'pending') {
              showCategoryToast('Your account is waiting for admin approval.');
            } else if (data.status === 'rejected') {
              showCategoryToast('Your account application has been rejected.');
            } else {
              showCategoryToast(data.error || '❌ Google Authentication failed.');
            }
            return;
          }

          // Save authenticated Google user session
          isUserAuthenticated = true;
          localStorage.setItem('ro_b2b_logged_in', 'true');
          localStorage.setItem('ro_b2b_token', data.user?.token || `RO_B2B_JWT_G_${Date.now()}`);
          localStorage.setItem('ro_b2b_user', JSON.stringify(data.user));

          const profileTitle = document.getElementById('profileBusinessTitle');
          if (profileTitle && data.user) {
            profileTitle.textContent = data.user.name || data.user.owner || 'Google Dealer Partner';
          }

          showCategoryToast(data.message || `🎉 Signed in as ${data.user.email}`);

          setTimeout(() => {
            navigateToScreen('home-tab');
          }, 300);
        } catch (err) {
          resetBtnState();
          console.error('[GOOGLE AUTH ERROR]', err);
          showCategoryToast('❌ Network error verifying Google account credentials.');
        }
      };

      let clientId = '';
      try {
        const configRes = await fetch('/api/auth/config');
        const configData = await configRes.json();
        clientId = configData?.googleClientId || '';
      } catch (cErr) {
        console.warn('[AUTH CONFIG NOTICE] Unable to fetch client ID:', cErr);
      }

      if (typeof window.google === 'undefined' || !window.google.accounts) {
        try {
          await this.loadGoogleGsiScript();
        } catch (loadErr) {
          resetBtnState();
          showCategoryToast('⚠️ Failed to load Google Identity Services SDK.');
          return;
        }
      }

      try {
        if (window.google && window.google.accounts && window.google.accounts.oauth2) {
          const client = window.google.accounts.oauth2.initTokenClient({
            client_id: clientId,
            scope: 'email profile openid',
            prompt: 'select_account',
            callback: (tokenRes) => {
              if (tokenRes.error) {
                resetBtnState();
                if (tokenRes.error === 'popup_closed_by_user') {
                  showCategoryToast('⚠️ Google Sign-In popup was closed before selection.');
                } else {
                  showCategoryToast(`⚠️ Google OAuth Error (${tokenRes.error}): ${tokenRes.error_description || 'Authentication failed'}`);
                }
                return;
              }
              handleCredentialOrToken({ access_token: tokenRes.access_token });
            },
            error_callback: (err) => {
              resetBtnState();
              console.warn('[GIS TOKEN ERROR]', err);
              showCategoryToast('⚠️ Google Account popup blocked or closed.');
            }
          });

          client.requestAccessToken();
        } else if (window.google && window.google.accounts && window.google.accounts.id) {
          window.google.accounts.id.initialize({
            client_id: clientId,
            callback: (res) => handleCredentialOrToken({ credential: res.credential }),
            auto_select: false
          });

          window.google.accounts.id.prompt((notification) => {
            if (notification.isNotDisplayed() || notification.isSkippedMoment()) {
              resetBtnState();
              showCategoryToast(`⚠️ Google Account prompt notice: ${notification.getNotDisplayedReason() || 'Skipped'}`);
            }
          });
        } else {
          resetBtnState();
          showCategoryToast('⚠️ Google Identity Services unavailable.');
        }
      } catch (triggerErr) {
        resetBtnState();
        console.error('[GIS TRIGGER ERROR]', triggerErr);
        showCategoryToast(`⚠️ Google OAuth Error: ${triggerErr.message || 'Could not open Google Login'}`);
      }
    },

    loadGoogleGsiScript: function() {
      return new Promise((resolve, reject) => {
        if (window.google && window.google.accounts) return resolve();
        const script = document.createElement('script');
        script.src = 'https://accounts.google.com/gsi/client';
        script.async = true;
        script.defer = true;
        script.onload = resolve;
        script.onerror = reject;
        document.head.appendChild(script);
      });
    }
  };

  // Login Screen Event Listeners
  document.getElementById('loginForm')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const idInput = document.getElementById('loginIdentifierInput');
    const passInput = document.getElementById('loginPasswordInput');
    const errId = document.getElementById('errLoginId');
    const errPass = document.getElementById('errLoginPass');

    if (errId) errId.style.display = 'none';
    if (errPass) errPass.style.display = 'none';

    const idVal = (idInput?.value || '').trim();
    const passVal = (passInput?.value || '').trim();

    let hasErr = false;
    if (!idVal) {
      if (errId) errId.style.display = 'block';
      hasErr = true;
    }
    if (!passVal) {
      if (errPass) errPass.style.display = 'block';
      hasErr = true;
    }
    if (hasErr) return;

    const result = await B2BAuthService.loginWithPassword(idVal, passVal);
    if (result.success) {
      showCategoryToast('🎉 Welcome back! Login successful.');
      navigateToScreen('home-tab');
    } else {
      showCategoryToast(result.error);
    }
  });

  // Open OTP Login Screen (Enter Email to receive OTP)
  document.getElementById('btnOpenOtpMode')?.addEventListener('click', (e) => {
    e.preventDefault();
    const loginIdInput = document.getElementById('loginIdentifierInput');
    const otpEmailInput = document.getElementById('otpRequestEmailInput');
    const errElem = document.getElementById('errOtpRequestTarget');
    if (errElem) errElem.style.display = 'none';

    if (otpEmailInput && loginIdInput && loginIdInput.value.trim()) {
      otpEmailInput.value = loginIdInput.value.trim();
    }

    navigateToScreen('screen-request-otp');
    setTimeout(() => {
      if (otpEmailInput) otpEmailInput.focus();
    }, 150);
  });

  // Helper: Strict Email Address & Domain Typo Validator
  function isValidEmailAddress(emailStr) {
    if (!emailStr) return false;
    const clean = emailStr.trim().toLowerCase();

    // 1. Standard email format check (must have username@domain.tld)
    const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
    if (!emailRegex.test(clean)) return false;

    // 2. Reject common domain typos (e.g. gmil.com, gmaill.com, gamil.com, gmal.com, etc.)
    const invalidDomainTypos = [
      'gmil.com', 'gmaill.com', 'gmal.com', 'gamil.com', 'gmai.com', 'gmall.com',
      'gmaill.co', 'gmai.co', 'gamel.com', 'gemail.com', 'gimail.com',
      'yaho.com', 'yahoo.co', 'yaho.co', 'ymail.co',
      'hotmial.com', 'hotmai.com', 'outlok.com', 'icold.com'
    ];

    const parts = clean.split('@');
    if (parts.length === 2 && invalidDomainTypos.includes(parts[1])) {
      return false;
    }

    return true;
  }

  // Real-time email validation on input & blur
  const otpEmailInputElem = document.getElementById('otpRequestEmailInput');
  const errOtpElem = document.getElementById('errOtpRequestTarget');
  const boxOtpElem = document.getElementById('boxOtpRequestTarget');

  function validateOtpEmailTarget() {
    const targetVal = (otpEmailInputElem?.value || '').trim();
    if (!targetVal) return false;

    const isMobile = /^\d{10}$/.test(targetVal);
    const isValid = isValidEmailAddress(targetVal) || isMobile;

    if (!isValid) {
      if (errOtpElem) {
        errOtpElem.textContent = 'Please enter a valid email address.';
        errOtpElem.style.display = 'block';
      }
      if (boxOtpElem) boxOtpElem.classList.add('error');
      return false;
    } else {
      if (errOtpElem) errOtpElem.style.display = 'none';
      if (boxOtpElem) boxOtpElem.classList.remove('error');
      return true;
    }
  }

  if (otpEmailInputElem) {
    otpEmailInputElem.addEventListener('input', () => {
      const val = otpEmailInputElem.value.trim();
      if (val.includes('@') && val.length > 5) {
        validateOtpEmailTarget();
      } else {
        if (errOtpElem) errOtpElem.style.display = 'none';
        if (boxOtpElem) boxOtpElem.classList.remove('error');
      }
    });

    otpEmailInputElem.addEventListener('blur', () => {
      if (otpEmailInputElem.value.trim()) {
        validateOtpEmailTarget();
      }
    });
  }

  // Request OTP Form Submission Handler
  document.getElementById('otpRequestForm')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const targetInput = document.getElementById('otpRequestEmailInput');
    const errElem = document.getElementById('errOtpRequestTarget');
    const boxElem = document.getElementById('boxOtpRequestTarget');
    const targetVal = (targetInput?.value || '').trim();

    const isMobile = /^\d{10}$/.test(targetVal);
    const isValid = isValidEmailAddress(targetVal) || isMobile;

    if (!targetVal || !isValid) {
      if (errElem) {
        errElem.textContent = 'Please enter a valid email address.';
        errElem.style.display = 'block';
      }
      if (boxElem) boxElem.classList.add('error');
      if (targetInput) targetInput.focus();
      return;
    }

    if (errElem) errElem.style.display = 'none';
    if (boxElem) boxElem.classList.remove('error');

    await B2BAuthService.sendOTP(targetVal);
  });

  // Back to Password Login Link Handlers
  document.getElementById('linkBackToPasswordLogin')?.addEventListener('click', (e) => {
    e.preventDefault();
    navigateToScreen('screen-login');
  });

  document.getElementById('btnBackFromOtpRequest')?.addEventListener('click', (e) => {
    e.preventDefault();
    navigateToScreen('screen-login');
  });

  document.getElementById('btnGoogleSignIn')?.addEventListener('click', (e) => {
    e.preventDefault();
    B2BAuthService.signInWithGoogle();
  });

  document.getElementById('linkSignUp')?.addEventListener('click', (e) => {
    e.preventDefault();
    navigateToScreen('screen-register');
  });

  // OTP 6-Digit Auto-Focus, Digit Filtering & Clipboard Paste Handlers
  const otpBoxes = document.querySelectorAll('.otp-digit-box');
  otpBoxes.forEach((box, idx) => {
    box.addEventListener('input', (e) => {
      box.value = box.value.replace(/\D/g, '');
      if (box.value.length === 1 && idx < otpBoxes.length - 1) {
        otpBoxes[idx + 1].focus();
      }
    });

    box.addEventListener('keydown', (e) => {
      if (e.key === 'Backspace' && !box.value && idx > 0) {
        otpBoxes[idx - 1].focus();
      }
    });

    box.addEventListener('paste', (e) => {
      e.preventDefault();
      const pasteData = (e.clipboardData || window.clipboardData).getData('text').replace(/\D/g, '');
      if (pasteData) {
        const digits = pasteData.slice(0, 6).split('');
        otpBoxes.forEach((b, i) => {
          b.value = digits[i] || '';
        });
        if (digits.length >= 6) {
          otpBoxes[5].focus();
        } else if (digits.length > 0) {
          otpBoxes[Math.min(digits.length, 5)].focus();
        }
      }
    });
  });

  let otpTimerInterval = null;
  function startOtpCountdownTimer() {
    let secondsLeft = 60; // 1 minute (60 seconds) resend timer
    const timerSpan = document.getElementById('otpTimerSpan');
    const timerText = document.getElementById('otpTimerText');
    const resendBtn = document.getElementById('btnResendOtp');

    if (timerSpan) timerSpan.style.display = 'inline';
    if (resendBtn) resendBtn.style.display = 'none';

    if (otpTimerInterval) clearInterval(otpTimerInterval);

    const updateTimerDisplay = (sec) => {
      const mins = Math.floor(sec / 60);
      const secs = sec % 60;
      if (timerText) {
        timerText.textContent = `${mins < 10 ? '0' + mins : mins}:${secs < 10 ? '0' + secs : secs}`;
      }
    };

    updateTimerDisplay(secondsLeft);

    otpTimerInterval = setInterval(() => {
      secondsLeft--;
      updateTimerDisplay(secondsLeft);

      if (secondsLeft <= 0) {
        clearInterval(otpTimerInterval);
        if (timerSpan) timerSpan.style.display = 'none';
        if (resendBtn) resendBtn.style.display = 'inline-block';
      }
    }, 1000);

    // Auto-focus first digit box
    setTimeout(() => {
      if (otpBoxes[0]) otpBoxes[0].focus();
    }, 200);
  }

  // Resend OTP Button Handler
  document.getElementById('btnResendOtp')?.addEventListener('click', (e) => {
    e.preventDefault();
    B2BAuthService.resendOTP();
  });

  // Change Target Button Handler
  document.getElementById('btnEditTarget')?.addEventListener('click', (e) => {
    e.preventDefault();
    navigateToScreen('screen-request-otp');
    document.getElementById('otpRequestEmailInput')?.focus();
  });

  // Verify OTP Action Handler (Strict 6-Digit Verification Check)
  document.getElementById('btnVerifyOtp')?.addEventListener('click', async (e) => {
    e.preventDefault();
    let enteredCode = '';
    otpBoxes.forEach(b => enteredCode += b.value.trim());

    if (!enteredCode || enteredCode.length < 6 || !/^\d{6}$/.test(enteredCode)) {
      showCategoryToast('⚠️ Please enter full 6-digit OTP code');
      otpBoxes.forEach(b => {
        b.style.borderColor = '#EF4444';
        setTimeout(() => b.style.borderColor = '#CBD5E1', 2500);
      });
      return;
    }

    const verificationResult = await B2BAuthService.verifyOTP(enteredCode);

    if (verificationResult.success) {
      showCategoryToast('🎉 Verification Successful! Redirecting to Dealer Portal...');
      setTimeout(() => {
        navigateToScreen('home-tab');
      }, 700);
    } else {
      showCategoryToast(verificationResult.error || '❌ Invalid OTP code entered.');
      otpBoxes.forEach(b => {
        b.style.borderColor = '#EF4444';
        setTimeout(() => b.style.borderColor = '#CBD5E1', 2500);
      });
    }
  });

  // Sign Up Form Submission with Strict Field Validation
  document.getElementById('dealerRegForm')?.addEventListener('submit', async (e) => {
    e.preventDefault();

    // Reset error messages & styling
    const errName = document.getElementById('errRegName');
    const errMobile = document.getElementById('errRegMobile');
    const errEmail = document.getElementById('errRegEmail');
    const errPass = document.getElementById('errRegPass');
    const errConfirmPass = document.getElementById('errRegConfirmPass');
    const errAddress = document.getElementById('errRegAddress');

    [errName, errMobile, errEmail, errPass, errConfirmPass, errAddress].forEach(el => {
      if (el) el.style.display = 'none';
    });

    const boxName = document.getElementById('boxRegName');
    const boxMobile = document.getElementById('boxRegMobile');
    const boxEmail = document.getElementById('boxRegEmail');
    const boxPass = document.getElementById('boxRegPass');
    const boxConfirmPass = document.getElementById('boxRegConfirmPass');
    const boxAddress = document.getElementById('boxRegAddress');

    [boxName, boxMobile, boxEmail, boxPass, boxConfirmPass, boxAddress].forEach(el => {
      if (el) el.classList.remove('error');
    });

    const nameVal = (document.getElementById('regOwnerName')?.value || '').trim();
    const mobileVal = (document.getElementById('regMobile')?.value || '').replace(/\D/g, '');
    const emailVal = (document.getElementById('regEmail')?.value || '').trim().toLowerCase();
    const passVal = (document.getElementById('regPassword')?.value || '').trim();
    const confirmPassVal = (document.getElementById('regConfirmPassword')?.value || '').trim();
    const addressVal = (document.getElementById('regAddress')?.value || '').trim();

    let hasValidationError = false;

    // 1. Name validation
    if (!nameVal) {
      if (errName) errName.style.display = 'block';
      if (boxName) boxName.classList.add('error');
      hasValidationError = true;
    }

    // 2. Mobile validation (exactly 10 digits)
    if (!mobileVal || mobileVal.length !== 10) {
      if (errMobile) errMobile.style.display = 'block';
      if (boxMobile) boxMobile.classList.add('error');
      hasValidationError = true;
    }

    // 3. Email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailVal || !emailRegex.test(emailVal)) {
      if (errEmail) errEmail.style.display = 'block';
      if (boxEmail) boxEmail.classList.add('error');
      hasValidationError = true;
    }

    // 4. Password validation (must contain at least 8 characters)
    if (!passVal || passVal.length < 8) {
      if (errPass) errPass.style.display = 'block';
      if (boxPass) boxPass.classList.add('error');
      hasValidationError = true;
    }

    // 5. Confirm Password match
    if (!confirmPassVal || confirmPassVal !== passVal) {
      if (errConfirmPass) errConfirmPass.style.display = 'block';
      if (boxConfirmPass) boxConfirmPass.classList.add('error');
      hasValidationError = true;
    }

    // 6. Address validation
    if (!addressVal) {
      if (errAddress) errAddress.style.display = 'block';
      if (boxAddress) boxAddress.classList.add('error');
      hasValidationError = true;
    }

    if (hasValidationError) return;

    // Submit Application to Backend
    const signUpResult = await B2BAuthService.submitSignUp({
      name: nameVal,
      mobile: mobileVal,
      email: emailVal,
      password: passVal,
      confirmPassword: confirmPassVal,
      address: addressVal
    });

    if (signUpResult.success) {
      document.getElementById('dealerRegForm')?.reset();
      
      // Auto pre-fill login credentials for immediate login
      const loginIdInput = document.getElementById('loginIdentifierInput');
      const loginPassInput = document.getElementById('loginPasswordInput');
      if (loginIdInput) loginIdInput.value = emailVal;
      if (loginPassInput) loginPassInput.value = passVal;

      showCategoryToast('🎉 Account Created Successfully! You can now log in immediately.');
      navigateToScreen('screen-submitted');
    } else {
      showCategoryToast(signUpResult.error);
    }
  });

  // Application Submitted Screen Handler -> Navigates ONLY to Login
  document.getElementById('btnGoToLogin')?.addEventListener('click', () => {
    navigateToScreen('screen-login');
  });

  // Account Approved Screen Handler -> Navigates ONLY to Login (NO auto-login!)
  document.getElementById('btnLoginNow')?.addEventListener('click', () => {
    navigateToScreen('screen-login');
  });

  // Checkout Screen Handlers
  document.getElementById('btnContinueToPayment')?.addEventListener('click', async () => {
    let userData = {};
    try {
      userData = JSON.parse(localStorage.getItem('ro_b2b_user') || '{}');
    } catch(e) {}
    const email = userData.email || '';

    if (!email) {
      showCategoryToast('⚠️ Please login to place an order.');
      return;
    }

    if (!cartState || cartState.length === 0) {
      showCategoryToast('⚠️ Your cart is empty.');
      return;
    }

    const selectedAddrObj = (window.cachedUserAddresses || []).find(a => a.id === window.selectedCheckoutAddressId) || (window.cachedUserAddresses || [])[0];
    const formattedAddr = selectedAddrObj ? 
      `${selectedAddrObj.fullName || userData.name || 'Recipient'}${selectedAddrObj.businessName ? ' (' + selectedAddrObj.businessName + ')' : ''}, ${selectedAddrObj.street}${selectedAddrObj.area ? ', ' + selectedAddrObj.area : ''}, ${selectedAddrObj.city}, ${selectedAddrObj.state || 'Tamil Nadu'} - ${selectedAddrObj.pincode} (Ph: +91 ${selectedAddrObj.phone})` : 
      (userData.address || 'Wholesale Dealer Hub');

    const noteVal = document.getElementById('deliveryNoteInput')?.value.trim() || '';
    const payRadio = document.querySelector('input[name="payMethod"]:checked');
    const payMethodVal = payRadio ? payRadio.value : 'upi';
    const payMethodStr = payMethodVal === 'upi' ? 'UPI / QR Direct Transfer' : (payMethodVal === 'credit' ? 'B2B Wholesale Credit (15 Days)' : 'Cash on Delivery (COD)');

    let subtotal = cartState.reduce((sum, item) => sum + (item.numericPrice * item.quantity), 0);
    let discount = Math.round(subtotal * 0.10);
    let gst = Math.round((subtotal - discount) * 0.18);
    let deliveryFee = subtotal > 5000 ? 0 : 250;
    let grandTotal = (subtotal - discount) + gst + deliveryFee;

    const btn = document.getElementById('btnContinueToPayment');
    const origBtnHTML = btn ? btn.innerHTML : 'Continue to Payment';
    if (btn) {
      btn.disabled = true;
      btn.innerHTML = '<span>Processing Order...</span> <i class="fas fa-spinner fa-spin"></i>';
    }

    try {
      const res = await fetch('/api/user/orders/create', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: email,
          items: cartState,
          subtotal: subtotal,
          discount: discount,
          gst: gst,
          deliveryFee: deliveryFee,
          grandTotal: grandTotal,
          paymentMethod: payMethodStr,
          deliveryAddress: formattedAddr,
          deliveryNote: noteVal
        })
      });

      const data = await res.json();
      if (btn) {
        btn.disabled = false;
        btn.innerHTML = origBtnHTML;
      }

      if (!res.ok || !data.success) {
        showCategoryToast(data.error || '❌ Failed to place order.');
        return;
      }

      showCategoryToast(data.message || '🎉 Order Placed Successfully! B2B GST Invoice Generated.');
      cartState = [];
      updateCartUI();

      setTimeout(() => {
        navigateToScreen('my-orders-tab');
        if (typeof window.loadUserOrderHistory === 'function') {
          window.loadUserOrderHistory();
        }
      }, 1000);
    } catch(err) {
      if (btn) {
        btn.disabled = false;
        btn.innerHTML = origBtnHTML;
      }
      showCategoryToast('❌ Network error placing order.');
    }
  });

  // Logout Handler
  document.getElementById('btnLogoutApp')?.addEventListener('click', () => {
    isUserAuthenticated = false;
    localStorage.removeItem('ro_b2b_logged_in');
    localStorage.removeItem('ro_b2b_token');
    localStorage.removeItem('ro_b2b_user');
    screenHistoryStack = [];

    if (window.google && window.google.accounts && window.google.accounts.id) {
      window.google.accounts.id.disableAutoSelect();
    }

    showCategoryToast('Logged out successfully.');
    navigateToScreen('screen-login');
  });

  // Categories Grid Card Clicks
  document.querySelectorAll('.category-full-card').forEach(card => {
    card.addEventListener('click', () => {
      const catKey = card.getAttribute('data-category') || 'all';
      const catName = card.querySelector('.category-full-card-title')?.textContent.trim() || 'Products';
      
      if (catKey === 'systems' || catName.toLowerCase().includes('ro')) {
        openModal('roCategoriesSubModal');
        showCategoryToast('Opening RO Product Categories & Systems Hub...');
        return;
      }

      showCategoryToast(`Opening Category: ${catName}`);
      navigateToScreen('products-tab');
      filterProductsByCategory(catKey, catName);
    });
  });

  // Bottom Navigation Click Handler
  document.querySelectorAll('#mainBottomNav .nav-item').forEach(item => {
    item.addEventListener('click', () => {
      const targetTab = item.getAttribute('data-tab');
      if (targetTab) navigateToScreen(targetTab);
    });
  });

  // Replace default tab switcher
  function switchTab(targetTabId, updateHistory = true) {
    navigateToScreen(targetTabId, updateHistory);
  }

  // Handle Browser Back / Forward buttons
  window.addEventListener('popstate', (e) => {
    if (productModal && productModal.style.display === 'flex') {
      closeProductDetails(false);
    } else if (e.state && e.state.screen) {
      navigateToScreen(e.state.screen, false);
    }
  });

  // 4. Category Cards Click & Filter Handler
  const categoryCards = document.querySelectorAll('.category-card');
  const searchInput = document.querySelector('.search-input');

  categoryCards.forEach(card => {
    card.style.cursor = 'pointer';

    const handleCategoryClick = (e) => {
      e.preventDefault();
      const catName = card.querySelector('.category-title')?.textContent.trim() || 'All';
      const catKey = card.getAttribute('data-category') || catName.toLowerCase();

      if (catKey === 'systems' || catName.toLowerCase().includes('ro')) {
        openModal('roCategoriesSubModal');
        showCategoryToast('Opening RO Product Categories & Systems Hub...');
        return;
      }

      showCategoryToast(`Opening Category: ${catName}`);
      switchTab('products-tab');
      filterProductsByCategory(catKey, catName);
    };

    card.addEventListener('click', handleCategoryClick);
  });

  // Comprehensive Category-Specific Product Database (Category -> Products -> Full Specifications, Features & Applications)
  const catalogProducts = [
    // RO SYSTEMS CATEGORY
    {
      id: "sys_1",
      category: "systems",
      brand: "AquaClean",
      name: "Commercial RO Water Filter 50 LPH",
      price: 18500,
      mrp: 24000,
      moq: "MOQ: 2 Units",
      badge: "SAVE 23%",
      rating: "★★★★★ (24)",
      img: "purifier.jpg",
      sku: "SYS-50LPH-COMM",
      desc: "High-capacity 50 LPH Commercial Reverse Osmosis Water Purification System engineered for commercial plants, schools, hostels, and restaurants. Built with dual booster pumps, twin membranes, and heavy-duty stainless steel skid structure.",
      specs: {
        flow: "50 LPH (13.2 GPH)",
        rejection: "98.5% High Rejection",
        pressure: "80 - 145 PSI",
        warranty: "1 Year B2B Warranty"
      },
      features: [
        "Dual 100 GPD Heavy-Duty Copper Motor Booster Pumps",
        "Twin High Rejection 75 GPD TFC Reverse Osmosis Membranes",
        "Food-Grade Polypropylene 5 Micron Sediment & Carbon Pre-Filters",
        "Integrated Pressure Gauge & TDS Monitor Interface",
        "Heavy-Duty Stainless Steel Skid Frame with Anti-Vibration Pads"
      ],
      applications: "Commercial Offices, Schools, Hostels, Hotels, Restaurants, Factory Canteens & Bottling Units"
    },
    {
      id: "sys_2",
      category: "systems",
      brand: "PureFlow",
      name: "Industrial Stainless RO Plant 250 LPH",
      price: 48000,
      mrp: 62000,
      moq: "MOQ: 1 Unit",
      badge: "HEAVY DUTY",
      rating: "★★★★★ (18)",
      img: "purifier.jpg",
      sku: "SYS-250LPH-IND",
      desc: "Industrial-grade 250 LPH Reverse Osmosis Plant featuring SS 304 pressure vessel vessels, vertical multistage high pressure pump, and micro-computer auto-flushing controller.",
      specs: {
        flow: "250 LPH (66 GPH)",
        rejection: "99.2% High Rejection",
        pressure: "120 - 220 PSI",
        warranty: "1 Year B2B Warranty"
      },
      features: [
        "SS 304 Grade Heavy Industrial Skid Frame & High Pressure Piping",
        "Vertical Multistage High-Pressure Stainless Pump",
        "Automatic Membrane Auto-Flushing & Dry-Run Protection",
        "Digital Flow Meters & Dual In-Line Pressure Indicators"
      ],
      applications: "Pharma Manufacturing, Bottling Plants, Commercial Laundry, Hospitals & Large Institutions"
    },
    {
      id: "sys_3",
      category: "systems",
      brand: "AquaClean",
      name: "RO Storage Tank 15L White",
      price: 1750,
      mrp: 2300,
      moq: "MOQ: 1 Unit",
      badge: "IN STOCK",
      rating: "★★★★★ (19)",
      img: "tank.jpg",
      sku: "TANK-15L-WHT",
      desc: "NSF/ANSI Standard 58 certified hydro-pneumatic pressurized water storage tank. Designed with food-grade butyl diaphragm and stainless steel 1/4\" NPT connection valve.",
      specs: {
        flow: "15 Liters Storage",
        rejection: "NSF 58 Certified",
        pressure: "100 PSI Max Rating",
        warranty: "6 Months Warranty"
      },
      features: [
        "100% Food-Grade Virgin Polypropylene Outer Shell",
        "Seamless Internal Butyl Rubber Diaphragm Chamber",
        "Pre-Pressurized Internal Air Chamber with Brass Valve Core",
        "Corrosion Proof & Leak-Tested Pressure Cell"
      ],
      applications: "Under-Sink Commercial & Residential Water Purifiers, Water Coolers & Dispensers"
    },
    {
      id: "sys_4",
      category: "systems",
      brand: "HydroShield",
      name: "Commercial Dual RO Skid Assembly 100 LPH",
      price: 32000,
      mrp: 41000,
      moq: "MOQ: 1 Unit",
      badge: "GST CREDIT",
      rating: "★★★★★ (31)",
      img: "purifier.jpg",
      sku: "SYS-100LPH-DUAL",
      desc: "Commercial 100 LPH Skid Assembly equipped with twin high-flow commercial membranes, dual high-pressure pumps, low-voltage auto cutoff, and integrated sediment filtration.",
      specs: {
        flow: "100 LPH (26.4 GPH)",
        rejection: "98.8% High Rejection",
        pressure: "90 - 160 PSI",
        warranty: "1 Year B2B Warranty"
      },
      features: [
        "Twin High-Flow Commercial RO Membrane Housings",
        "Dual Heavy-Duty Commercial Booster Pump Motors",
        "High/Low Pressure Cut-off Switch Protection",
        "Stainless Steel Frame Structure with Compact Footprint"
      ],
      applications: "Restaurants, Office Complexes, Food Processing Units, Commercial Kitchens"
    },

    // MEMBRANES CATEGORY
    {
      id: "mem_1",
      category: "membranes",
      brand: "Vontron",
      name: "RO Membrane 75 GPD Filter Element",
      price: 850,
      mrp: 1200,
      moq: "MOQ: 10 Units",
      badge: "HOT DEAL",
      rating: "★★★★★ (48)",
      img: "membrane.jpg",
      sku: "MEM-VON-75GPD",
      desc: "Original Vontron 75 GPD Thin-Film Composite (TFC) Reverse Osmosis Membrane element. Delivers up to 98.5% salt rejection in hard brackish water up to 2000 PPM TDS.",
      specs: {
        flow: "75 GPD (283 LPD)",
        rejection: "98.5% Salt Rejection",
        pressure: "60 - 100 PSI",
        warranty: "6 Months Warranty"
      },
      features: [
        "Advanced Polyamide Thin-Film Composite (TFC) Sheets",
        "High Rejection Rate for Heavy Metals, Fluoride, Arsenic & TDS",
        "Dry-Packed Sealed Cell for Extended Shelf Life",
        "NSF/ANSI Standard 58 Certified Filter Material"
      ],
      applications: "Residential & Commercial RO Systems, Borewell Water Filtration"
    },
    {
      id: "mem_2",
      category: "membranes",
      brand: "Filmtec",
      name: "Filmtec 100 GPD High TDS Rejection Membrane",
      price: 1250,
      mrp: 1700,
      moq: "MOQ: 10 Units",
      badge: "ORIGINAL",
      rating: "★★★★★ (64)",
      img: "membrane.jpg",
      sku: "MEM-FLM-100GPD",
      desc: "Premium DuPont Filmtec 100 GPD RO Membrane element engineered for extreme high TDS groundwater up to 3500 PPM. Delivers consistent pure water recovery.",
      specs: {
        flow: "100 GPD (378 LPD)",
        rejection: "98.8% Salt Rejection",
        pressure: "70 - 120 PSI",
        warranty: "1 Year B2B Warranty"
      },
      features: [
        "Precision Spun Polyamide Spiral Layer Tech",
        "Handles High TDS Borewell Water up to 3500 PPM",
        "Resistant to Hardness Scaling & Organic Fouling",
        "Made with Certified USA Material Technology"
      ],
      applications: "High TDS Ground Water, Industrial Pre-Filtration, High Flow Coolers"
    },
    {
      id: "mem_3",
      category: "membranes",
      brand: "CSM",
      name: "CSM 80 GPD Commercial Grade Membrane",
      price: 980,
      mrp: 1350,
      moq: "MOQ: 5 Units",
      badge: "BULK DEAL",
      rating: "★★★★★ (27)",
      img: "membrane.jpg",
      sku: "MEM-CSM-80GPD",
      desc: "CSM Toray 80 GPD Commercial RO Membrane Sheet element providing low energy operation, high permeate output, and superior hardness rejection.",
      specs: {
        flow: "80 GPD (302 LPD)",
        rejection: "98.0% Salt Rejection",
        pressure: "60 - 110 PSI",
        warranty: "6 Months Warranty"
      },
      features: [
        "Toray Advanced Membrane Sheet Construction",
        "Stable Flow Rate in Variable Pressure & Temperature",
        "High Rejection of Dissolved Salts, Nitrates & Chlorides"
      ],
      applications: "Domestic RO Systems, Commercial Dispensers, Under-Sink Coolers"
    },
    {
      id: "mem_4",
      category: "membranes",
      brand: "Vontron",
      name: "Vontron 4040 Commercial Industrial Membrane",
      price: 6800,
      mrp: 8900,
      moq: "MOQ: 1 Unit",
      badge: "HIGH FLOW",
      rating: "★★★★★ (15)",
      img: "membrane.jpg",
      sku: "MEM-VON-4040",
      desc: "Industrial Vontron LP21-4040 Low Pressure RO Membrane. Designed for commercial RO plants requiring high permeate flow rate (2400 GPD) at low operating pressure.",
      specs: {
        flow: "2400 GPD (9000 LPD)",
        rejection: "99.5% Salt Rejection",
        pressure: "150 - 220 PSI",
        warranty: "1 Year B2B Warranty"
      },
      features: [
        "85 sq.ft Active Membrane Surface Area",
        "Low Operating Pressure Design for Energy Savings",
        "Fiberglass Outer Wrap Protection Shell",
        "High Rejection for Industrial Process Water"
      ],
      applications: "250-1000 LPH Commercial & Industrial RO Plants, Bottling Plants"
    },

    // BOOSTER PUMPS CATEGORY
    {
      id: "pump_1",
      category: "pumps",
      brand: "E-Chen",
      name: "E-Chen 100 GPD Booster Pump 24V DC",
      price: 2450,
      mrp: 3200,
      moq: "MOQ: 1 Unit",
      badge: "TOP SELLER",
      rating: "★★★★★ (32)",
      img: "cat_pump_transparent.png",
      sku: "PUMP-ECH-100GPD",
      desc: "Original E-Chen 100 GPD 24V DC Heavy-Duty Booster Pump motor. Built with 100% pure copper motor winding, low vibration dampers, and self-priming suction capacity.",
      specs: {
        flow: "1.8 Liters Per Min",
        rejection: "24V DC / 1.2A",
        pressure: "80 - 125 PSI Working",
        warranty: "1 Year B2B Warranty"
      },
      features: [
        "100% Pure Copper Motor Winding for 24/7 Continuous Duty",
        "Self-Priming Suction Lift up to 2 Meters",
        "Low Noise & Low Vibration Rubber Mounting Feet",
        "NSF Certified High Pressure Polypropylene Pump Head"
      ],
      applications: "75-100 GPD Domestic & Commercial Reverse Osmosis Water Purifiers"
    },
    {
      id: "pump_2",
      category: "pumps",
      brand: "BNQS",
      name: "BNQS 75 GPD Heavy Duty Copper Motor Pump",
      price: 1950,
      mrp: 2600,
      moq: "MOQ: 2 Units",
      badge: "100% COPPER",
      rating: "★★★★★ (41)",
      img: "cat_pump_transparent.png",
      sku: "PUMP-BNQ-75GPD",
      desc: "BNQS 75 GPD High-Torque Booster Pump Motor. Offers reliable operating pressure for standard domestic RO purifiers operating on municipal or tank water supply.",
      specs: {
        flow: "1.5 Liters Per Min",
        rejection: "24V DC / 0.9A",
        pressure: "70 - 110 PSI Working",
        warranty: "6 Months Warranty"
      },
      features: [
        "Heavy Copper Magnet Winding",
        "Leak-Proof Diaphragm Mechanism",
        "Low Power Consumption & Heat Dissipation"
      ],
      applications: "Household Under-Sink & Wall-Mount RO Purifiers"
    },
    {
      id: "pump_3",
      category: "pumps",
      brand: "Kemflo",
      name: "Kemflo 48V Commercial High Pressure Pump",
      price: 3850,
      mrp: 4900,
      moq: "MOQ: 1 Unit",
      badge: "48V POWER",
      rating: "★★★★★ (22)",
      img: "cat_pump_transparent.png",
      sku: "PUMP-KEM-48V",
      desc: "Heavy Commercial Kemflo 48V DC High Pressure Booster Pump Motor. Ideal for multi-membrane commercial RO plants requiring up to 180 PSI operating pressure.",
      specs: {
        flow: "3.5 Liters Per Min",
        rejection: "48V DC / 2.5A",
        pressure: "120 - 180 PSI Working",
        warranty: "1 Year B2B Warranty"
      },
      features: [
        "High Torque 48V Industrial Motor Core",
        "Dual Bearing Drive Shaft Assembly",
        "Heavy-Duty Metal Casing & Pressure Relief Valve"
      ],
      applications: "100-250 LPH Commercial RO Plants, Water Vending Machines"
    },
    {
      id: "pump_4",
      category: "pumps",
      brand: "E-Chen",
      name: "E-Chen 150 GPD Commercial Booster Pump 36V",
      price: 3100,
      mrp: 4200,
      moq: "MOQ: 1 Unit",
      badge: "HIGH PRESSURE",
      rating: "★★★★★ (39)",
      img: "cat_pump_transparent.png",
      sku: "PUMP-ECH-150GPD",
      desc: "E-Chen 150 GPD 36V DC Commercial Booster Pump. Provides enhanced pressure and flow rate for high-capacity commercial RO systems.",
      specs: {
        flow: "2.5 Liters Per Min",
        rejection: "36V DC / 1.8A",
        pressure: "90 - 140 PSI Working",
        warranty: "1 Year B2B Warranty"
      },
      features: [
        "Precision High Pressure Diaphragm Head",
        "36V High Output Motor Winding",
        "Vibration Absorption Mounting Brackets"
      ],
      applications: "Dual Membrane Commercial RO Systems, Commercial Water Coolers"
    },

    // FILTERS CATEGORY
    {
      id: "flt_1",
      category: "filters",
      brand: "AquaClean",
      name: "CTO Carbon Block Filter 10 Inch",
      price: 180,
      mrp: 250,
      moq: "MOQ: 25 Units",
      badge: "BULK STOCK",
      rating: "★★★★★ (15)",
      img: "cat_spares.jpg",
      sku: "FLT-CTO-10IN",
      desc: "Compressed 10\" Extruded CTO Carbon Block Filter Cartridge. Absorbs chlorine, volatile organic compounds (VOCs), bad odor, and protects RO membrane from chemical damage.",
      specs: {
        flow: "5 Liters Per Min",
        rejection: "99% Chlorine Removal",
        pressure: "100 PSI Max Rating",
        warranty: "6 Months Replacement"
      },
      features: [
        "Premium Extruded Coconut Shell Activated Carbon",
        "Outer Polypropylene Wrap for Sediment Pre-Filtering",
        "Food-Grade Gaskets Prevent Bypass Leakage",
        "High Chlorine, Odor & Organic Chemical Absorption"
      ],
      applications: "Pre-RO Filtration Stage in Commercial & Domestic Water Systems"
    },
    {
      id: "flt_2",
      category: "filters",
      brand: "PureFlow",
      name: "PP Meltblown Sediment Filter 5 Micron",
      price: 120,
      mrp: 180,
      moq: "MOQ: 25 Units",
      badge: "BEST VALUE",
      rating: "★★★★★ (52)",
      img: "cat_filter.jpg",
      sku: "FLT-PP-5MIC",
      desc: "Spun Polypropylene 5 Micron Meltblown Sediment Filter Cartridge. Effectively traps mud, rust, silt, sand, and suspended particles.",
      specs: {
        flow: "8 Liters Per Min",
        rejection: "5 Micron Rating",
        pressure: "90 PSI Max Rating",
        warranty: "3 Months Replacement"
      },
      features: [
        "100% Pure Melt-Blown Polypropylene Fibers",
        "Graded Density Structure for Extended Dirt Holding",
        "Thermal Bonded Microfibers (No Chemical Binders)"
      ],
      applications: "Primary Pre-Filter Stage for Domestic & Commercial RO Purifiers"
    },
    {
      id: "flt_3",
      category: "filters",
      brand: "AquaClean",
      name: "GAC Granular Activated Carbon Inline Filter",
      price: 210,
      mrp: 290,
      moq: "MOQ: 20 Units",
      badge: "ODOR REMOVAL",
      rating: "★★★★★ (36)",
      img: "cat_spares.jpg",
      sku: "FLT-GAC-INLINE",
      desc: "10\" Inline Granular Activated Carbon (GAC) Filter Cartridge with 1/4\" quick connect fittings. Removes residual chlorine, organic tastes, and odors.",
      specs: {
        flow: "3 Liters Per Min",
        rejection: "High Adsorption GAC",
        pressure: "80 PSI Max Rating",
        warranty: "6 Months Warranty"
      },
      features: [
        "High Surface Area Coconut Shell Carbon Granules",
        "1/4\" Quick-Connect Push Fitting Port",
        "Prevents RO Membrane Chemical Degradation"
      ],
      applications: "Pre-Membrane Chemical Treatment & Post-Carbon Water Polishing"
    },
    {
      id: "flt_4",
      category: "filters",
      brand: "HydroShield",
      name: "Inline T33 Post Carbon Taste Filter",
      price: 150,
      mrp: 220,
      moq: "MOQ: 30 Units",
      badge: "FRESH WATER",
      rating: "★★★★★ (28)",
      img: "cat_filter.jpg",
      sku: "FLT-T33-POST",
      desc: "Final stage T33 Post Carbon Inline Filter Cartridge. Imparts sweet natural taste to purified water and removes any residual storage tank odors.",
      specs: {
        flow: "2 Liters Per Min",
        rejection: "Post RO Polishing",
        pressure: "75 PSI Max Rating",
        warranty: "6 Months Warranty"
      },
      features: [
        "Silver-Impregnated Anti-Bacterial Coconut Carbon",
        "Enhances Drinking Water Taste & Clarity",
        "Simple Push-Fit Connection Design"
      ],
      applications: "Final Polishing Stage in RO Purifiers, Dispensers & Coolers"
    },

    // SPARE PARTS CATEGORY
    {
      id: "spr_1",
      category: "spares",
      brand: "HydroShield",
      name: "Big Blue 20 Inch Heavy Duty Filter Housing",
      price: 650,
      mrp: 900,
      moq: "MOQ: 10 Units",
      badge: "HEAVY DUTY",
      rating: "★★★★★ (28)",
      img: "cat_filter.jpg",
      sku: "HOU-BB-20IN",
      desc: "20\" Big Blue Heavy-Duty Filter Housing with 1\" NPT stainless steel threaded ports. Fits standard 20\" x 4.5\" jumbo filter cartridges.",
      specs: {
        flow: "40 Liters Per Min",
        rejection: "1\" NPT Port Size",
        pressure: "125 PSI Max Rating",
        warranty: "1 Year B2B Warranty"
      },
      features: [
        "Thick-Walled Reinforced Polypropylene Body",
        "Pressure Relief Button for Easy Cartridge Changes",
        "Double O-Ring Leak-Proof Ring Seal System"
      ],
      applications: "Whole-House Pre-Filtration, Commercial RO Plants, Softener Pre-Filter"
    },
    {
      id: "spr_2",
      category: "spares",
      brand: "AquaClean",
      name: "Automatic Shut-Off (ASO) Valve 1/4 Inch",
      price: 85,
      mrp: 130,
      moq: "MOQ: 50 Units",
      badge: "AUTO SHUT",
      rating: "★★★★★ (45)",
      img: "cat_spares.jpg",
      sku: "VAL-ASO-14IN",
      desc: "Four-way 1/4\" Quick-Connect Automatic Shut-Off (ASO) Valve. Automatically halts feed water supply to membrane when storage tank is full.",
      specs: {
        flow: "1/4\" Push Fittings",
        rejection: "67% Shut-off Ratio",
        pressure: "100 PSI Max Rating",
        warranty: "6 Months Replacement"
      },
      features: [
        "100% Food Grade Polypropylene Housing",
        "High Sensitivity Internal Diaphragm",
        "Saves Water & Prevents Waste Overflow"
      ],
      applications: "Automatic Water Control in Domestic & Commercial Under-Sink RO Units"
    },
    {
      id: "spr_3",
      category: "spares",
      brand: "E-Chen",
      name: "24V 2.5A SMPS Power Adapter Supply",
      price: 420,
      mrp: 600,
      moq: "MOQ: 10 Units",
      badge: "POWER ADAPTER",
      rating: "★★★★★ (33)",
      img: "cat_spares.jpg",
      sku: "PWR-SMPS-24V",
      desc: "Switch Mode Power Supply (SMPS) 24V DC 2.5A Power Adapter. Provides regulated DC voltage for RO booster pumps and solenoid valves.",
      specs: {
        flow: "Output 24V DC 2.5A",
        rejection: "Input 100-240V AC",
        pressure: ">85% Power Efficiency",
        warranty: "1 Year B2B Warranty"
      },
      features: [
        "Over-Voltage, Over-Current & Short-Circuit Protection",
        "Fire-Retardant ABS External Enclosure",
        "Stable Constant Current Output Design"
      ],
      applications: "Powering 75-100 GPD Booster Pumps, Solenoid Valves & UV Lamps"
    },
    {
      id: "spr_4",
      category: "spares",
      brand: "AquaClean",
      name: "High / Low Pressure Switch Set for RO",
      price: 140,
      mrp: 200,
      moq: "MOQ: 30 Units",
      badge: "PRECISE CONTROL",
      rating: "★★★★★ (19)",
      img: "cat_spares.jpg",
      sku: "SWI-HPLS-SET",
      desc: "Dual High & Low Pressure Switch Protection Assembly with 1/4\" quick connect fittings. Automatically shuts off pump during low water pressure or when tank is full.",
      specs: {
        flow: "1/4\" Push Connect",
        rejection: "24V/36V DC Rating",
        pressure: "5 PSI Low / 40 PSI High",
        warranty: "6 Months Warranty"
      },
      features: [
        "Low Pressure Switch Prevents Dry-Running Pump Damage",
        "High Pressure Switch Cuts Off Pump When Tank Fills",
        "Silver Alloy Electrical Contact Terminals"
      ],
      applications: "Electrical Safety & Automation in Domestic & Commercial RO Purifiers"
    }
  ];

  function renderCatalogProducts(categoryKey = 'all') {
    const catalogContainer = document.getElementById('productsCatalog');

    let filtered = catalogProducts;
    if (categoryKey && categoryKey !== 'all') {
      filtered = catalogProducts.filter(item => {
        if (item.category === categoryKey) return true;
        const cat = (item.category || '').toLowerCase();
        const name = (item.name || '').toLowerCase();
        const desc = (item.desc || '').toLowerCase();

        if (categoryKey === 'pipes') return cat === 'spares' || name.includes('pipe') || name.includes('tubing') || desc.includes('tubing') || desc.includes('pipe');
        if (categoryKey === 'accessories') return cat === 'spares' || name.includes('fitting') || name.includes('connector') || desc.includes('fitting') || desc.includes('valve');
        return false;
      });
      if (filtered.length === 0) filtered = catalogProducts;
    }

    const countBadge = document.getElementById('catalogCountTag');
    if (countBadge) {
      countBadge.textContent = `${filtered.length} ITEMS LIVE`;
    }

    // HTML for Catalog Page (.pearl-product-card)
    const catalogHTML = filtered.map(item => `
      <div class="pearl-product-card popular-product-card" data-product-id="${item.id}">
        <div class="pearl-img-stage">
          <span class="pearl-discount-badge">${item.badge}</span>
          <button class="pearl-wishlist-btn"><i class="far fa-heart"></i></button>
          <img src="${item.img}" alt="${item.name}">
        </div>
        <span class="pearl-product-brand">${item.brand}</span>
        <h5 class="pearl-product-title">${item.name}</h5>
        <div class="pearl-rating-row">
          <span class="pearl-rating-stars">${item.rating.split(' ')[0]}</span>
          <span class="pearl-rating-count">${item.rating.split(' ')[1]}</span>
        </div>
        <div class="pearl-price-row">
          <div class="pearl-price-col">
            <span class="pearl-dealer-price">₹${item.price.toLocaleString('en-IN')}</span>
            <span class="pearl-mrp-price">MRP ₹${item.mrp.toLocaleString('en-IN')}</span>
            <span class="pearl-moq-tag">${item.moq}</span>
          </div>
          <button class="pearl-add-btn popular-add-btn" data-id="${item.id}" data-name="${item.name}" data-price="${item.price}" data-img="${item.img}">+</button>
        </div>
      </div>
    `).join('');

    if (catalogContainer) catalogContainer.innerHTML = catalogHTML;
  }

  function filterProductsByCategory(categoryKey, categoryName = '') {
    let key = categoryKey ? categoryKey.toLowerCase().trim() : 'all';

    const validKeys = ['all', 'systems', 'membranes', 'pumps', 'filters', 'spares', 'pipes', 'accessories'];
    if (!validKeys.includes(key)) {
      const combined = (key + ' ' + categoryName).toLowerCase();
      if (combined.includes('system')) key = 'systems';
      else if (combined.includes('membrane')) key = 'membranes';
      else if (combined.includes('pump') || combined.includes('booster')) key = 'pumps';
      else if (combined.includes('filter')) key = 'filters';
      else if (combined.includes('pipe') || combined.includes('tubing')) key = 'pipes';
      else if (combined.includes('spare') || combined.includes('valve')) key = 'spares';
      else if (combined.includes('accessori') || combined.includes('fitting')) key = 'accessories';
      else key = 'all';
    }

    // 1. Highlight active pill in Catalog tab
    const allPills = document.querySelectorAll('.catalog-pill, .catalog-pearl-pill, .catalog-cyber-pill');
    allPills.forEach(p => {
      const pKey = (p.getAttribute('data-category') || '').toLowerCase().trim();
      if (pKey === key || (key === 'all' && pKey === 'all')) {
        p.classList.add('active');
      } else {
        p.classList.remove('active');
      }
    });

    // 2. Highlight active Category Card on Home tab
    const homeCategoryCards = document.querySelectorAll('#home-tab .category-card');
    homeCategoryCards.forEach(c => {
      const cKey = (c.getAttribute('data-category') || '').toLowerCase().trim();
      if (cKey === key || (key === 'all' && cKey === 'all')) {
        c.classList.add('active');
      } else {
        c.classList.remove('active');
      }
    });

    renderCatalogProducts(key);
  }

  // Global Event Delegation for Catalog Category Pills
  document.addEventListener('click', (e) => {
    const pill = e.target.closest('.catalog-pill, .catalog-pearl-pill, .catalog-cyber-pill');
    if (pill) {
      e.preventDefault();
      const catKey = pill.getAttribute('data-category') || 'all';
      const catName = pill.textContent.trim();
      showCategoryToast(`Viewing: ${catName}`);
      filterProductsByCategory(catKey, catName);
    }
  });

  // Search Bar Real-Time Filter
  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      const query = e.target.value.toLowerCase().trim();
      const productCards = document.querySelectorAll('.product-card, .popular-product-card');

      productCards.forEach(card => {
        const title = card.querySelector('.product-name, .popular-name')?.textContent.toLowerCase() || '';
        const brand = card.querySelector('.product-brand')?.textContent.toLowerCase() || '';

        if (query === '' || title.includes(query) || brand.includes(query)) {
          card.style.display = 'flex';
        } else {
          card.style.display = 'none';
        }
      });
    });
  }

  // 6. Comprehensive Product Database for Dynamic Routing
  const productDatabase = {
    'booster pump': {
      slug: 'boosterpump',
      name: 'E-Chen 100 GPD Heavy Duty Booster Pump 24V DC',
      brand: 'E-CHEN',
      sku: 'PMP-100G-ECHEN',
      price: '₹2,450',
      mrp: 'MRP ₹3,200',
      moq: 'MOQ: 1 Unit',
      stock: 'IN STOCK',
      imgSrc: 'cat_pump.jpg',
      desc: 'Heavy-duty 100 GPD 24V DC Diaphragm Booster Pump for domestic and commercial RO water purifiers. Engineered with 100% pure copper motor winding, low-noise vibration dampers, and continuous 24-hour operation rating up to 125 PSI.',
      specFlow: '1.8 LPM @ 80 PSI',
      specRejection: '98.5% High Efficiency',
      specPressure: '60 - 125 PSI Continuous',
      specWarranty: '1 Year B2B Replacement Warranty'
    },
    'ro storage tank': {
      slug: 'rostoragetank',
      name: 'RO Hydro-Pneumatic Water Storage Tank 15L',
      brand: 'AQUA CLEAN',
      sku: 'TNK-15L-STAINLESS',
      price: '₹1,750',
      mrp: 'MRP ₹2,400',
      moq: 'MOQ: 1 Unit',
      stock: 'IN STOCK',
      imgSrc: 'tank.jpg',
      desc: 'Food-grade stainless steel internal bladder pressure storage tank for RO water purifiers. Holds 15 liters of pure purified water under pre-pressurized air chamber for instantaneous water flow.',
      specFlow: '15 Liters (3.2 Gallon)',
      specRejection: '100% Food Grade Polypropylene',
      specPressure: '50 PSI Max Pressure',
      specWarranty: '1 Year Manufacturer Warranty'
    },
    'pp sediment filter': {
      slug: 'ppsedimentfilter',
      name: '10 Inch Spun PP Sediment Filter 5 Micron',
      brand: 'AQUA CLEAN',
      sku: 'FLT-10IN-SPUN5M',
      price: '₹120',
      mrp: 'MRP ₹220',
      moq: 'MOQ: 25 Units',
      stock: 'IN STOCK',
      imgSrc: 'cat_filter.jpg',
      desc: 'Melt-blown 5 Micron 10-inch polypropylene sediment filter cartridge. Effectively traps suspended particles, sand, rust, silt, and dirt before feed water enters the RO membrane.',
      specFlow: '5 Micron Rating',
      specRejection: '99% Dirt Trapping Efficiency',
      specPressure: 'Standard 10" Pre-Filter Housing',
      specWarranty: '100% Genuine Certified'
    },
    'cto carbon filter': {
      slug: 'ctocarbonfilter',
      name: '10 Inch CTO Extruded Carbon Block Filter Cartridge',
      brand: 'VONTRON',
      sku: 'FLT-10IN-CTOBLK',
      price: '₹180',
      mrp: 'MRP ₹300',
      moq: 'MOQ: 25 Units',
      stock: 'IN STOCK',
      imgSrc: 'cat_spares.jpg',
      desc: 'Premium activated coconut shell carbon block filter element. Removes chlorine, bad taste, organic odor, turbidity, and chemical impurities for fresh drinking water.',
      specFlow: '10 Inch Standard Block',
      specRejection: '> 95% Chlorine Reduction',
      specPressure: 'Service Life 6000 Liters',
      specWarranty: 'Food Grade NSF/ANSI Certified'
    },
    'commercial ro water filter 50 lph': {
      slug: 'commercialro50lph',
      name: 'Commercial RO Water Purifier Plant 50 LPH',
      brand: 'AQUATECH',
      sku: 'SYS-50LPH-COMM',
      price: '₹18,500',
      mrp: 'MRP ₹24,000',
      moq: 'MOQ: 2 Units',
      stock: 'IN STOCK',
      imgSrc: 'purifier.jpg',
      desc: 'Heavy-duty 50 LPH Commercial Reverse Osmosis Water Purification System. Features dual 100 GPD booster pumps, twin Vontron membranes, fully automatic TDS controller, and stainless steel frame.',
      specFlow: '50 Liters / Hour',
      specRejection: '98.5% Salt Rejection',
      specPressure: 'Dual Heavy Duty Pumps',
      specWarranty: '1 Year Full B2B Warranty'
    },
    'ro membrane 75 gpd filter': {
      slug: 'vontron75gpd',
      name: 'Vontron 75 GPD RO Membrane High Rejection Element',
      brand: 'VONTRON',
      sku: 'MEM-75G-VONTRON',
      price: '₹850',
      mrp: 'MRP ₹1,450',
      moq: 'MOQ: 10 Units',
      stock: 'IN STOCK',
      imgSrc: 'membrane.jpg',
      desc: 'Original Vontron 75 GPD Thin-Film Composite (TFC) reverse osmosis membrane element. Provides 98.5% salt rejection in hard water up to 2000 PPM TDS.',
      specFlow: '75 GPD (283 LPD)',
      specRejection: '98.5% High Rejection',
      specPressure: '60 - 100 PSI Operating',
      specWarranty: 'NSF/ANSI Standard 58'
    }
  };

  // Helper to extract product details from card
  function getProductDetailsFromCard(card) {
    const productId = card.getAttribute('data-product-id');
    let item = null;

    if (productId) {
      item = catalogProducts.find(p => p.id === productId || p.id === 'pump_' + productId || p.id === 'sys_' + productId || p.id === 'mem_' + productId || p.id === 'flt_' + productId || p.id === 'spr_' + productId);
    }

    if (!item) {
      const rawTitle = card.querySelector('.product-name, .popular-name, .pearl-product-title, .cyber-product-title')?.textContent.trim() || '';
      const key = rawTitle.toLowerCase();

      item = catalogProducts.find(p => {
        const pName = p.name.toLowerCase();
        return pName === key || pName.includes(key) || key.includes(pName) ||
               (key.includes('booster pump') && p.id === 'pump_1') ||
               (key.includes('storage tank') && p.id === 'sys_3') ||
               (key.includes('sediment filter') && p.id === 'flt_2') ||
               (key.includes('carbon block') && p.id === 'flt_1') ||
               (key.includes('big blue') && p.id === 'spr_1') ||
               (key.includes('membrane') && p.id === 'mem_1');
      });
    }

    if (item) {
      return {
        slug: item.id,
        name: item.name,
        brand: item.brand,
        price: typeof item.price === 'number' ? `₹${item.price.toLocaleString('en-IN')}` : item.price,
        mrp: typeof item.mrp === 'number' ? `MRP ₹${item.mrp.toLocaleString('en-IN')}` : item.mrp,
        moq: item.moq,
        badge: item.badge,
        stock: 'IN STOCK',
        imgSrc: item.img,
        sku: item.sku || `SKU-${item.id.toUpperCase()}`,
        desc: item.desc,
        specs: item.specs,
        features: item.features,
        applications: item.applications
      };
    }

    const rawTitle = card.querySelector('.product-name, .popular-name, .pearl-product-title, .cyber-product-title')?.textContent.trim() || '';
    const key = rawTitle.toLowerCase();

    let details = productDatabase[key];
    if (!details) {
      const matchedKey = Object.keys(productDatabase).find(k => key.includes(k) || k.includes(key));
      if (matchedKey) {
        details = productDatabase[matchedKey];
      } else {
        const brand = card.querySelector('.product-brand, .pearl-product-brand')?.textContent.trim() || 'AQUACLEAN';
        const price = card.querySelector('.wholesale-price, .popular-price, .pearl-dealer-price')?.textContent.trim() || '₹850';
        const moq = card.querySelector('.product-moq, .popular-moq, .pearl-moq-tag')?.textContent.trim() || 'MOQ: 1 Unit';
        const imgSrc = card.querySelector('img')?.getAttribute('src') || 'purifier.jpg';
        const cleanSlug = rawTitle.toLowerCase().replace(/[^a-z0-9]/g, '');

        details = {
          slug: cleanSlug || 'productdetails',
          name: rawTitle || 'RO Component',
          brand: brand,
          price: price,
          moq: moq,
          imgSrc: imgSrc,
          sku: 'RO-PARTS-2026',
          desc: 'High-grade commercial & domestic RO water purification component.'
        };
      }
    }
    return details;
  }

  // 7. PRODUCT DETAILS MODAL VIEW HANDLERS
  const productModal = document.getElementById('productDetailsModal');
  const closeProductModalBtn = document.getElementById('closeProductModal');
  const modalImg = document.getElementById('modalProductImg');
  const modalTitle = document.getElementById('modalProductName');
  const modalBrand = document.getElementById('modalProductBrand');
  const modalSku = document.getElementById('modalProductSku');
  const modalPrice = document.getElementById('modalProductPrice');
  const modalMrp = document.getElementById('modalProductMrp');
  const modalMoq = document.getElementById('modalProductMoq');
  const modalDesc = document.getElementById('modalProductDesc');
  const modalStock = document.getElementById('modalProductStock');
  const modalAddToCartBtn = document.getElementById('modalAddToCartBtn');
  const modalBuyNowBtn = document.getElementById('modalBuyNowBtn');
  let currentModalProduct = null;

  function openProductDetails(productData, updateUrl = true) {
    if (!productModal) return;

    if (typeof productData === 'string') {
      const foundItem = catalogProducts.find(p => p.id === productData || p.sku === productData);
      if (foundItem) {
        productData = {
          slug: foundItem.id,
          name: foundItem.name,
          brand: foundItem.brand,
          price: typeof foundItem.price === 'number' ? `₹${foundItem.price.toLocaleString('en-IN')}` : foundItem.price,
          mrp: typeof foundItem.mrp === 'number' ? `MRP ₹${foundItem.mrp.toLocaleString('en-IN')}` : foundItem.mrp,
          moq: foundItem.moq,
          badge: foundItem.badge,
          stock: 'IN STOCK',
          imgSrc: foundItem.img,
          sku: foundItem.sku || `SKU-${foundItem.id.toUpperCase()}`,
          desc: foundItem.desc,
          specs: foundItem.specs,
          features: foundItem.features,
          applications: foundItem.applications
        };
      } else {
        const dbItem = Object.values(productDatabase).find(p => p.slug === productData.toLowerCase() || p.sku === productData);
        if (dbItem) {
          productData = dbItem;
        } else {
          productData = {
            slug: productData,
            name: 'RO Purifier Component',
            brand: 'AQUACLEAN',
            price: '₹850',
            mrp: 'MRP ₹1,200',
            moq: 'MOQ: 1 Unit',
            stock: 'IN STOCK',
            imgSrc: 'purifier.jpg',
            sku: productData,
            desc: 'High-grade commercial & domestic RO water purification component.'
          };
        }
      }
    }

    currentModalProduct = productData;

    if (modalImg) modalImg.src = productData.imgSrc || productData.img || 'purifier.jpg';
    if (modalTitle) modalTitle.textContent = productData.name;
    if (modalBrand) modalBrand.textContent = (productData.brand || 'AQUACLEAN').toUpperCase();
    if (modalSku) modalSku.textContent = `SKU: ${productData.sku || 'RO-PART-2026'}`;
    if (modalPrice) modalPrice.textContent = productData.price;
    if (modalMrp) modalMrp.textContent = productData.mrp || ('MRP ₹' + Math.round(parseInt((productData.price || '850').replace(/\D/g, '')) * 1.35));
    if (modalMoq) modalMoq.textContent = productData.moq || 'MOQ: 1 Unit';
    if (modalStock) modalStock.textContent = productData.stock || 'IN STOCK';
    if (modalDesc) modalDesc.textContent = productData.desc || 'High-grade commercial & domestic RO water purification component.';

    // Populate Dynamic Specs Table
    const specFlow = document.getElementById('specFlow');
    const specRejection = document.getElementById('specRejection');
    const specPressure = document.getElementById('specPressure');
    const specWarranty = document.getElementById('specWarranty');

    if (specFlow) specFlow.textContent = productData.specs?.flow || productData.specFlow || '50 LPH / 75 GPD';
    if (specRejection) specRejection.textContent = productData.specs?.rejection || productData.specRejection || '98.5% High Rejection';
    if (specPressure) specPressure.textContent = productData.specs?.pressure || productData.specPressure || '60 - 125 PSI';
    if (specWarranty) specWarranty.textContent = productData.specs?.warranty || productData.specWarranty || '1 Year B2B Warranty';

    // Populate Key Features
    const featuresList = document.getElementById('modalFeaturesList');
    if (featuresList) {
      if (productData.features && Array.isArray(productData.features)) {
        featuresList.innerHTML = productData.features.map(f => `<li><i class="fas fa-check-circle" style="color: #10B981; margin-right: 6px;"></i> ${f}</li>`).join('');
      } else {
        featuresList.innerHTML = `
          <li><i class="fas fa-check-circle" style="color: #10B981; margin-right: 6px;"></i> 100% Pure Copper Motor Winding for 24/7 continuous operation</li>
          <li><i class="fas fa-check-circle" style="color: #10B981; margin-right: 6px;"></i> NSF/ANSI Standard 58 Certified for safe drinking water</li>
          <li><i class="fas fa-check-circle" style="color: #10B981; margin-right: 6px;"></i> Food-grade high pressure polypropylene casing</li>
          <li><i class="fas fa-check-circle" style="color: #10B981; margin-right: 6px;"></i> Low vibration & noise reduction dampers</li>
        `;
      }
    }

    // Populate Applications
    const appText = document.getElementById('modalProductApplications');
    if (appText) {
      appText.textContent = productData.applications || 'Commercial Offices, Schools, Restaurants & Industrial Bottling Plants.';
    }

    productModal.style.display = 'flex';
    document.body.style.overflow = 'hidden';

    if (updateUrl) {
      const slug = productData.slug || productData.name.toLowerCase().replace(/[^a-z0-9]/g, '');
      history.pushState({ modalOpen: true, productName: productData.name, slug: slug }, '', `#${slug}`);
    }
  }

  function closeProductDetails(triggerBack = true) {
    if (!productModal) return;
    productModal.style.display = 'none';
    document.body.style.overflow = '';

    if (triggerBack && history.state && history.state.modalOpen) {
      history.back();
    }
  }

  if (closeProductModalBtn) {
    closeProductModalBtn.addEventListener('click', () => closeProductDetails(true));
  }

  if (productModal) {
    productModal.addEventListener('click', (e) => {
      if (e.target === productModal) {
        closeProductDetails(true);
      }
    });
  }

  if (modalAddToCartBtn) {
    modalAddToCartBtn.addEventListener('click', () => {
      if (currentModalProduct) {
        addProductToCart(currentModalProduct, modalAddToCartBtn);
      }
    });
  }

  if (modalBuyNowBtn) {
    modalBuyNowBtn.addEventListener('click', () => {
      if (currentModalProduct) {
        addProductToCart(currentModalProduct);
        closeProductDetails(false);
        switchTab('orders-tab');
      }
    });
  }

  // Check URL Hash on Load for Direct Navigation (e.g., #boosterpump)
  function checkUrlHashRoute() {
    const hash = window.location.hash.replace('#', '').toLowerCase();
    if (!hash) return;

    if (hash === 'home-tab' || hash === 'products-tab' || hash === 'orders-tab' || hash === 'profile-tab') {
      switchTab(hash, false);
      return;
    }

    const matchedProduct = Object.values(productDatabase).find(p => p.slug === hash || hash.includes(p.slug));
    if (matchedProduct) {
      openProductDetails(matchedProduct, false);
    }
  }

  // 8. UNIFIED EVENT DELEGATION: Add to Cart (+) & Product Details Modal
  document.addEventListener('click', (e) => {
    const addBtn = e.target.closest('.popular-add-btn, .pearl-add-btn');
    if (addBtn) {
      e.preventDefault();
      e.stopPropagation();
      const id = addBtn.getAttribute('data-id');
      const name = addBtn.getAttribute('data-name');
      const price = addBtn.getAttribute('data-price');
      const img = addBtn.getAttribute('data-img');

      const productObj = {
        sku: id || 'RO-' + Date.now(),
        name: name || 'RO Component',
        price: typeof price === 'number' ? `₹${price}` : (price.startsWith('₹') ? price : `₹${price}`),
        imgSrc: img || 'purifier.jpg'
      };
      addProductToCart(productObj, addBtn);
      showCategoryToast(`Added to Cart: ${name}`);
      return;
    }

    const card = e.target.closest('.product-card, .popular-product-card, .pearl-product-card');
    if (card) {
      if (e.target.closest('.heart-btn, .pearl-wishlist-btn')) {
        return;
      }

      e.preventDefault();
      const details = getProductDetailsFromCard(card);
      openProductDetails(details, true);
    }
  });

  // Header Cart Button Click Handler -> Switch to Cart tab
  const headerCartBtn = document.getElementById('headerCartBtn');
  if (headerCartBtn) {
    headerCartBtn.addEventListener('click', () => {
      switchTab('orders-tab');
    });
  }

  // Quick Action Metric Cards Click Handlers
  document.querySelectorAll('.metric-action-card').forEach(card => {
    card.style.cursor = 'pointer';
    card.addEventListener('click', () => {
      const title = card.querySelector('.metric-action-title')?.textContent.trim() || '';
      if (title.includes('Track') || title.includes('Reorder')) {
        switchTab('orders-tab');
        showCategoryToast('Opening Orders Tracker...');
      } else {
        showCategoryToast(`${title} Request Submitted!`);
      }
    });
  });

  // Hero Explore Products Button Click Handler
  document.querySelectorAll('.btn-explore, .promo-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      switchTab('products-tab');
    });
  });

  // Wishlist Heart Buttons
  document.querySelectorAll('.heart-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      btn.style.color = '#EF4444';
      showCategoryToast('Added to Wishlist!');
    });
  });

  // 9. Interactive Toast Notification
  function showCategoryToast(message) {
    window.showCategoryToastRef = showCategoryToast;
    let toast = document.getElementById('categoryToast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'categoryToast';
      toast.style.cssText = `
        position: absolute;
        bottom: 75px;
        left: 50%;
        transform: translateX(-50%);
        background: #0F62FE;
        color: white;
        padding: 10px 16px;
        border-radius: 20px;
        font-size: 11.5px;
        font-weight: 700;
        box-shadow: 0 8px 24px rgba(15, 98, 254, 0.4);
        z-index: 99999;
        transition: all 0.3s ease;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
        width: max-content;
        max-width: calc(100% - 32px);
        box-sizing: border-box;
        text-align: center;
        word-break: break-word;
        line-height: 1.4;
      `;
      const targetFrame = document.querySelector('.phone-frame') || document.querySelector('.app-container') || document.body;
      targetFrame.appendChild(toast);
    }

    toast.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="white"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg> ${message}`;
    toast.style.opacity = '1';

    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => {
      toast.style.opacity = '0';
    }, 2000);
  }

  // 10. Product Loading Simulation
  function simulateProductLoading() {
    const skeleton = document.getElementById('productsSkeleton');
    const catalog = document.getElementById('productsCatalog');
    
    if (skeleton && catalog) {
      skeleton.style.display = 'block';
      catalog.style.display = 'none';

      setTimeout(() => {
        skeleton.style.display = 'none';
        catalog.style.display = 'block';
      }, 300);
    }
  }

  // 11. SECTION 6 EXCLUSIVE DEALER PRICING AUTO-SLIDING CAROUSEL
  const promoTrack = document.getElementById('promoCarouselTrack');
  const promoDots = document.querySelectorAll('.promo-dot-node');
  let currentPromoIndex = 0;
  let promoAutoPlayTimer = null;

  function scrollToPromoSlide(index) {
    if (!promoTrack) return;
    const slides = promoTrack.querySelectorAll('.promo-slide-card');
    if (index >= slides.length) index = 0;
    if (index < 0) index = slides.length - 1;

    currentPromoIndex = index;
    const targetSlide = slides[currentPromoIndex];
    if (targetSlide) {
      promoTrack.scrollTo({
        left: targetSlide.offsetLeft,
        behavior: 'smooth'
      });
    }

    promoDots.forEach((dot, idx) => {
      dot.classList.toggle('active', idx === currentPromoIndex);
    });
  }

  if (promoTrack) {
    // Update active dot on scroll / swipe
    promoTrack.addEventListener('scroll', () => {
      const slides = promoTrack.querySelectorAll('.promo-slide-card');
      const scrollPos = promoTrack.scrollLeft;
      const slideWidth = promoTrack.clientWidth;
      
      const activeIdx = Math.round(scrollPos / slideWidth);
      if (activeIdx !== currentPromoIndex && activeIdx >= 0 && activeIdx < slides.length) {
        currentPromoIndex = activeIdx;
        promoDots.forEach((dot, idx) => {
          dot.classList.toggle('active', idx === currentPromoIndex);
        });
      }
    });

    // Dot Clicks
    promoDots.forEach((dot, idx) => {
      dot.addEventListener('click', () => {
        scrollToPromoSlide(idx);
        restartPromoAutoPlay();
      });
    });

    // Promo Pill Buttons Click -> Switch to Catalog
    document.querySelectorAll('.btn-promo-pill').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const target = btn.getAttribute('data-target') || 'products-tab';
        switchTab(target);
        showCategoryToast('Opening Wholesale Catalog...');
      });
    });

    // Automatic Slide Timer (Every 3.5 Seconds)
    function startPromoAutoPlay() {
      promoAutoPlayTimer = setInterval(() => {
        scrollToPromoSlide(currentPromoIndex + 1);
      }, 3500);
    }

    function restartPromoAutoPlay() {
      clearInterval(promoAutoPlayTimer);
      startPromoAutoPlay();
    }

    // Pause on Touch / Hover
    promoTrack.addEventListener('touchstart', () => clearInterval(promoAutoPlayTimer), { passive: true });
    promoTrack.addEventListener('mouseenter', () => clearInterval(promoAutoPlayTimer));
    promoTrack.addEventListener('mouseleave', () => startPromoAutoPlay());

    startPromoAutoPlay();
  }

  // 12. AUTOMATIC WHITE BACKGROUND REMOVER FOR PROMO CAROUSEL IMAGES
  function removeWhiteBgFromPromoImages() {
    const promoImages = document.querySelectorAll('.promo-stage-img-wrapper img');
    promoImages.forEach(img => {
      const processImage = () => {
        try {
          const canvas = document.createElement('canvas');
          const ctx = canvas.getContext('2d');
          canvas.width = img.naturalWidth || 300;
          canvas.height = img.naturalHeight || 300;
          ctx.drawImage(img, 0, 0, canvas.width, canvas.height);

          const imgData = ctx.getImageData(0, 0, canvas.width, canvas.height);
          const data = imgData.data;

          for (let i = 0; i < data.length; i += 4) {
            const r = data[i];
            const g = data[i + 1];
            const b = data[i + 2];

            // If pixel is white or near white (R > 210, G > 210, B > 210)
            if (r > 210 && g > 210 && b > 210) {
              data[i + 3] = 0; // Make alpha transparent!
            }
          }

          ctx.putImageData(imgData, 0, 0);
          img.src = canvas.toDataURL('image/png');
          img.style.mixBlendMode = 'normal'; // Reset mix blend mode after true transparency conversion!
        } catch (e) {
          console.log('Canvas background removal fallback:', e);
        }
      };

      if (img.complete) {
        processImage();
      } else {
        img.addEventListener('load', processImage);
      }
    });
  }

  removeWhiteBgFromPromoImages();

  // ==========================================================================
  // COMPREHENSIVE INTERACTIVE OPTION & MODAL HANDLERS
  // ==========================================================================
  
  function openModal(modalId) {
    const m = document.getElementById(modalId);
    if (m) {
      // Scroll app container & view to top so modal header is 100% visible
      const appContainer = document.querySelector('.app-container');
      if (appContainer) appContainer.scrollTop = 0;
      window.scrollTo(0, 0);

      m.style.display = 'flex';
      document.body.style.overflow = 'hidden';
    }
  }

  function closeModal(modalId) {
    const m = document.getElementById(modalId);
    if (m) {
      m.style.display = 'none';
      document.body.style.overflow = '';
    }
  }

  window.openModal = openModal;
  window.closeModal = closeModal;
  window.openSearchModal = openSearchModal;
  window.openNotificationsModal = function() {
    openModal('notificationsModal');
  };
  window.closeNotificationsModal = function() {
    closeModal('notificationsModal');
  };

  // 1. Lightning-Fast Instant Search Modal & Live Search Engine
  function openSearchModal(initialQuery = '') {
    const appContainer = document.querySelector('.app-container');
    if (appContainer) appContainer.scrollTop = 0;

    openModal('searchOverlayModal');
    
    const input = document.getElementById('globalSearchInput');
    if (input) {
      input.value = initialQuery;
      // Auto-place blinking cursor directly inside search input
      const triggerFocus = () => {
        try {
          input.focus();
          input.setSelectionRange(input.value.length, input.value.length);
        } catch(e) {}
      };
      triggerFocus();
      setTimeout(triggerFocus, 60);
      renderSearchResults(initialQuery);
    }
  }

  function renderSearchResults(query) {
    const listElem = document.getElementById('globalSearchResultsList');
    const countElem = document.getElementById('searchResultsCount');
    const clearBtn = document.getElementById('clearSearchBtn');

    if (!listElem) return;

    const q = (query || '').trim().toLowerCase();
    const singularQ = q.endsWith('s') && q.length > 2 ? q.slice(0, -1) : q;

    if (clearBtn) {
      clearBtn.style.display = q.length > 0 ? 'block' : 'none';
    }

    const matchedProducts = catalogProducts.filter(p => {
      if (!q) return true;
      const name = p.name.toLowerCase();
      const brand = p.brand.toLowerCase();
      const category = p.category.toLowerCase();
      const desc = p.desc.toLowerCase();
      const sku = p.sku.toLowerCase();

      return name.includes(q) || name.includes(singularQ) ||
             brand.includes(q) || brand.includes(singularQ) ||
             category.includes(q) || category.includes(singularQ) ||
             desc.includes(q) || desc.includes(singularQ) ||
             sku.includes(q);
    });

    if (countElem) {
      countElem.textContent = q ? `${matchedProducts.length} PRODUCTS FOUND FOR "${query}"` : `WHOLESALE CATALOG (${catalogProducts.length} ITEMS LIVE)`;
    }

    if (matchedProducts.length === 0) {
      listElem.innerHTML = `
        <div style="text-align: center; padding: 40px 16px; color: #64748B;">
          <i class="fas fa-search" style="font-size: 36px; color: #CBD5E1; margin-bottom: 12px; display: block;"></i>
          <h4 style="font-size: 15px; font-weight: 800; color: #1E293B; margin-bottom: 4px;">No products match "${query}"</h4>
          <p style="font-size: 12px; color: #64748B;">Try searching for "purifier", "membrane", "pump", "filter", or "tank".</p>
        </div>
      `;
      return;
    }

    listElem.innerHTML = matchedProducts.map(p => `
      <div class="search-result-item" data-id="${p.id}" style="display: flex; align-items: center; justify-content: space-between; padding: 12px; border-radius: 16px; background: #F8FAFC; border: 1px solid #E2E8F0; cursor: pointer; transition: all 0.2s ease;">
        <div style="display: flex; align-items: center; gap: 12px; flex: 1; min-width: 0;">
          <div style="width: 50px; height: 50px; border-radius: 12px; background: white; border: 1px solid #E2E8F0; display: flex; align-items: center; justify-content: center; overflow: hidden; flex-shrink: 0;">
            <img src="${p.img}" alt="${p.name}" style="max-width: 100%; max-height: 100%; object-fit: contain;">
          </div>
          <div style="flex: 1; min-width: 0;">
            <div style="font-size: 8.5px; font-weight: 850; color: #0F62FE; text-transform: uppercase;">${p.brand}</div>
            <div style="font-size: 12.5px; font-weight: 800; color: #0F172A; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${p.name}</div>
            <div style="display: flex; align-items: center; gap: 8px; margin-top: 2px;">
              <span style="font-size: 13.5px; font-weight: 900; color: #0F62FE;">₹${p.price.toLocaleString()}</span>
              <span style="font-size: 9px; color: #64748B; font-weight: 700;">${p.moq}</span>
            </div>
          </div>
        </div>
        <button class="search-add-btn" data-id="${p.id}" style="width: 34px; height: 34px; border-radius: 50%; background: linear-gradient(135deg, #0F62FE 0%, #0043CE 100%); color: white; border: none; font-size: 16px; font-weight: 900; cursor: pointer; display: flex; align-items: center; justify-content: center; flex-shrink: 0; box-shadow: 0 4px 12px rgba(15, 98, 254, 0.25);">
          +
        </button>
      </div>
    `).join('');

    listElem.querySelectorAll('.search-result-item').forEach(item => {
      item.addEventListener('click', (e) => {
        const pId = item.getAttribute('data-id');
        if (e.target.closest('.search-add-btn')) {
          e.stopPropagation();
          const targetAddBtn = e.target.closest('.search-add-btn');
          const pData = catalogProducts.find(x => x.id === pId);
          if (pData) {
            addProductToCart({
              sku: pData.sku || pData.id,
              name: pData.name,
              brand: pData.brand,
              price: typeof pData.price === 'number' ? `₹${pData.price.toLocaleString('en-IN')}` : pData.price,
              moq: pData.moq,
              imgSrc: pData.img
            }, targetAddBtn);
          }
          return;
        }

        closeModal('searchOverlayModal');
        openProductDetails(pId);
      });
    });
  }

  // RO Subcategory Hub Handlers
  document.getElementById('closeRoCatModal')?.addEventListener('click', () => {
    closeModal('roCategoriesSubModal');
  });

  document.querySelectorAll('.ro-subcategory-card').forEach(card => {
    card.addEventListener('click', () => {
      const catKey = card.getAttribute('data-category') || 'systems';
      const title = card.getAttribute('data-title') || 'RO Products';
      closeModal('roCategoriesSubModal');
      showCategoryToast(`Opening ${title}`);
      navigateToScreen('products-tab');
      filterProductsByCategory(catKey, title);
    });
  });

  // Universal Top Header & Icon Buttons Event Delegation
  document.addEventListener('click', (e) => {
    // Search Trigger (Header search button, categories search button, search box, search input, filter icon, or any button containing fa-search)
    const searchBtn = e.target.closest('#headerSearchBtn, #catHeaderSearchBtn, .search-box, .search-input, .filter-btn-square, [aria-label="Search"], button:has(.fa-search)');
    if (searchBtn && !searchBtn.closest('#searchOverlayModal')) {
      e.preventDefault();
      e.stopPropagation();
      const initVal = searchBtn.value || '';
      openSearchModal(initVal);
      return;
    }

    // Notifications Trigger (Header bell icon or any button containing fa-bell)
    const notifBtn = e.target.closest('#headerNotificationsBtn, [aria-label="Notifications"], button:has(.fa-bell)');
    if (notifBtn && !notifBtn.closest('#notificationsModal')) {
      e.preventDefault();
      e.stopPropagation();
      openModal('notificationsModal');
      return;
    }

    // Menu Drawer Trigger
    const menuBtn = e.target.closest('#headerMenuBtn, [aria-label="Open menu"]');
    if (menuBtn) {
      e.preventDefault();
      e.stopPropagation();
      openModal('sideNavDrawer');
      return;
    }
  });

  // Global Search Input typing handler inside modal
  const globalSearchInput = document.getElementById('globalSearchInput');
  if (globalSearchInput) {
    globalSearchInput.addEventListener('input', (e) => {
      renderSearchResults(e.target.value);
    });
    globalSearchInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        renderSearchResults(globalSearchInput.value);
      }
    });
  }

  // Clear Search button handler
  document.getElementById('clearSearchBtn')?.addEventListener('click', () => {
    if (globalSearchInput) {
      globalSearchInput.value = '';
      renderSearchResults('');
      globalSearchInput.focus();
    }
  });

  // Close Search modal button
  document.getElementById('closeSearchModal')?.addEventListener('click', () => {
    closeModal('searchOverlayModal');
  });

  // Trending search tag pills
  document.querySelectorAll('.search-tag-pill').forEach(pill => {
    pill.addEventListener('click', () => {
      const q = pill.getAttribute('data-query') || '';
      if (globalSearchInput) {
        globalSearchInput.value = q;
      }
      renderSearchResults(q);
    });
  });

  // Home Page Search Input focus/click handler -> Opens search modal
  const homeSearchInput = document.querySelector('.search-input');
  if (homeSearchInput) {
    homeSearchInput.addEventListener('click', (e) => {
      e.preventDefault();
      openSearchModal(homeSearchInput.value);
    });
    homeSearchInput.addEventListener('focus', (e) => {
      e.preventDefault();
      homeSearchInput.blur();
      openSearchModal('');
    });
  }

  // 1. Header Search Button & Search Modal
  document.getElementById('headerSearchBtn')?.addEventListener('click', (e) => {
    e.preventDefault();
    openSearchModal('');
  });

  // 2. Header Notifications Button & Modal Close
  document.getElementById('headerNotificationsBtn')?.addEventListener('click', (e) => {
    e.preventDefault();
    openModal('notificationsModal');
  });
  document.getElementById('closeNotificationsModal')?.addEventListener('click', () => {
    closeModal('notificationsModal');
  });

  // 3. Header Hamburger Menu Button & Side Drawer
  document.getElementById('headerMenuBtn')?.addEventListener('click', (e) => {
    e.preventDefault();
    openModal('sideNavDrawer');
  });
  document.getElementById('closeDrawerBtn')?.addEventListener('click', () => {
    closeModal('sideNavDrawer');
  });

  // Side Drawer Category Items (Fully Functional Navigation to Category Products)
  document.querySelectorAll('.drawer-category-item').forEach(item => {
    item.addEventListener('click', () => {
      const catKey = item.getAttribute('data-category') || 'all';
      const title = item.getAttribute('data-title') || 'Category Products';
      closeModal('sideNavDrawer');
      showCategoryToast(`Opening ${title}...`);
      navigateToScreen('products-tab');
      filterProductsByCategory(catKey, title);
      const appContainer = document.querySelector('.app-container');
      if (appContainer) appContainer.scrollTop = 0;
      window.scrollTo(0, 0);
    });
  });

  // Side Drawer Item Navigation (All Options Working & Clickable)
  document.querySelectorAll('.drawer-item').forEach(item => {
    item.addEventListener('click', () => {
      const action = item.getAttribute('data-drawer-action');
      closeModal('sideNavDrawer');

      switch (action) {
        case 'home':
          window.navigateToHomeScreen();
          break;
        case 'products':
          navigateToScreen('products-tab');
          break;
        case 'categories':
          navigateToScreen('categories-tab');
          break;
        case 'cart':
          navigateToScreen('orders-tab');
          break;
        case 'orders':
          if (window.openProfileOption) window.openProfileOption('orders');
          break;
        case 'addresses':
          if (window.openProfileOption) window.openProfileOption('addresses');
          break;
        case 'gst':
          if (window.openProfileOption) window.openProfileOption('gst');
          break;
        case 'profile':
          navigateToScreen('profile-tab');
          break;
        case 'password':
        case 'settings':
          if (window.openProfileOption) window.openProfileOption('password');
          break;
        case 'support':
          if (window.openProfileOption) window.openProfileOption('support');
          break;
        case 'logout':
          document.getElementById('btnLogoutApp')?.click();
          break;
      }
    });
  });

  // Dynamic Profile Renderer using currently logged-in user account data
  function renderUserProfileData() {
    let userData = {};
    try {
      userData = JSON.parse(localStorage.getItem('ro_b2b_user') || '{}');
    } catch (e) {
      console.warn('[PROFILE RENDER NOTICE] Failed to parse ro_b2b_user:', e);
    }

    const name = (userData.name || userData.owner || 'Approved Dealer').trim();
    const email = (userData.email || 'dealer@aqua.com').trim();
    const rawMobile = (userData.mobile || '9876543210').trim();
    const mobile = rawMobile.startsWith('+91') ? rawMobile : `+91 ${rawMobile}`;
    const business = (userData.business || `${name} Aqua Wholesale`).trim();

    const nameElem = document.getElementById('profileUserName');
    const emailElem = document.getElementById('profileUserEmail');
    const mobileElem = document.getElementById('profileUserMobile');
    const busElem = document.getElementById('profileUserBusiness');
    const avatarElem = document.getElementById('profileUserAvatar');
    const profileTitleElem = document.getElementById('profileBusinessTitle');

    if (nameElem) nameElem.textContent = name;
    if (emailElem) emailElem.textContent = email;
    if (mobileElem) mobileElem.textContent = mobile;
    if (busElem) busElem.textContent = business;
    if (profileTitleElem) profileTitleElem.textContent = business;

    if (avatarElem) {
      const initial = (name.charAt(0) || 'D').toUpperCase();
      avatarElem.textContent = initial;
    }

    // Load reward points info for currently logged-in user
    loadUserRewardPoints();
  }

  // ==========================================================================
  // REWARD POINTS MANAGEMENT (DYNAMIC PER USER ACCOUNT)
  // ==========================================================================
  async function loadUserRewardPoints() {
    let userData = {};
    try {
      userData = JSON.parse(localStorage.getItem('ro_b2b_user') || '{}');
    } catch(e) {}
    const email = userData.email || '';
    const container = document.getElementById('sectionRewardHistoryContainer');
    const totalPointsElem = document.getElementById('rewardsTotalPointsDisplay');
    const lifetimeElem = document.getElementById('rewardsLifetimeEarnedDisplay');
    const subtitleElem = document.getElementById('profileRewardPointsSubtitle');
    const countTagElem = document.getElementById('rewardsHistoryCountTag');

    if (!email) {
      if (container) container.innerHTML = `<div style="text-align: center; color: #64748B; padding: 20px;">Please login to view your reward points.</div>`;
      return;
    }

    try {
      const res = await fetch(`/api/user/rewards?email=${encodeURIComponent(email)}`);
      const data = await res.json();

      if (!res.ok || !data.success) {
        if (container) container.innerHTML = `<div style="text-align: center; color: #EF4444; padding: 20px;">Failed to load reward points.</div>`;
        return;
      }

      const totalPoints = data.totalPoints || 0;
      const totalEarned = data.totalPointsEarned || 0;
      const history = data.history || [];

      if (totalPointsElem) totalPointsElem.textContent = totalPoints.toLocaleString();
      if (lifetimeElem) lifetimeElem.textContent = `${totalEarned.toLocaleString()} Points`;
      if (subtitleElem) subtitleElem.textContent = `Total Points: ${totalPoints.toLocaleString()} Points • View Points History →`;
      if (countTagElem) countTagElem.textContent = `${history.length} ${history.length === 1 ? 'Order' : 'Orders'}`;

      if (container) {
        if (history.length === 0) {
          container.innerHTML = `
            <div style="background: var(--bg-surface); padding: 36px 20px; border-radius: 20px; border: 1px solid var(--border-color); text-align: center;">
              <div style="font-size: 38px; color: #F59E0B; margin-bottom: 10px;">⭐</div>
              <h4 style="font-size: 15px; font-weight: 850; color: #1E293B; margin-bottom: 4px;">No Reward Points Yet</h4>
              <p style="font-size: 11.5px; color: #64748B; margin-bottom: 16px;">Place a confirmed order to earn 5 reward points for every ₹100 spent!</p>
              <button onclick="navigateToScreen('products-tab')" style="background: #0F62FE; color: white; border: none; padding: 10px 20px; border-radius: 20px; font-size: 12px; font-weight: 850; cursor: pointer;">Shop Wholesale Deals</button>
            </div>
          `;
          return;
        }

        container.innerHTML = history.map(item => {
          const formattedDate = item.date ? new Date(item.date).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '19 Sep 2026';
          return `
            <div style="background: var(--bg-surface); border: 1px solid var(--border-color); border-radius: 18px; padding: 16px; box-shadow: 0 4px 14px rgba(0,0,0,0.02); display: flex; align-items: center; justify-content: space-between;">
              <div>
                <div style="font-size: 13.5px; font-weight: 900; color: #0F172A; display: flex; align-items: center; gap: 6px;">
                  <span>Order #${item.orderId}</span>
                </div>
                <div style="font-size: 12px; font-weight: 700; color: #475569; margin-top: 3px;">
                  Order Amount: ₹${(item.orderAmount || 0).toLocaleString()}
                </div>
                <div style="font-size: 11px; color: #64748B; margin-top: 2px;">
                  Date: ${formattedDate}
                </div>
              </div>
              <div style="display: flex; flex-direction: column; align-items: flex-end; gap: 4px;">
                <span style="font-size: 13.5px; font-weight: 900; color: #D97706; background: #FEF3C7; padding: 5px 12px; border-radius: 12px; border: 1px solid rgba(245, 158, 11, 0.3); display: inline-flex; align-items: center; gap: 4px;">
                  ⭐ +${item.pointsEarned} Pts
                </span>
                <span style="font-size: 9.5px; font-weight: 800; color: #10B981;">Credited</span>
              </div>
            </div>
          `;
        }).join('');
      }
    } catch (err) {
      console.error('Failed to load user reward points:', err);
      if (container) container.innerHTML = `<div style="text-align: center; color: #EF4444; padding: 20px;">Error loading reward points.</div>`;
    }
  }

  // Helper to pre-populate edit profile forms
  function populateEditProfileForm(userData) {
    const fullName = (userData.name || userData.owner || 'Priya Angel').trim();
    const nameParts = fullName.split(' ');
    const firstName = nameParts[0] || '';
    const lastName = nameParts.slice(1).join(' ') || '';

    // Modal fields
    if (document.getElementById('editProfileFirstNameInput')) document.getElementById('editProfileFirstNameInput').value = firstName;
    if (document.getElementById('editProfileLastNameInput')) document.getElementById('editProfileLastNameInput').value = lastName;
    if (document.getElementById('editProfileEmailInput')) document.getElementById('editProfileEmailInput').value = userData.email || 'priya@gmail.com';
    if (document.getElementById('editProfileMobileInput')) document.getElementById('editProfileMobileInput').value = (userData.mobile || '9876543210').replace(/\D/g, '');
    if (document.getElementById('editProfileBusinessInput')) document.getElementById('editProfileBusinessInput').value = userData.business || 'Priya Aqua Wholesale';
    if (document.getElementById('editProfileAddressInput')) document.getElementById('editProfileAddressInput').value = userData.address || 'Plot 42, Ambattur Industrial Estate, Chennai - 600058';

    // Section fields
    if (document.getElementById('editSectionFirstNameInput')) document.getElementById('editSectionFirstNameInput').value = firstName;
    if (document.getElementById('editSectionLastNameInput')) document.getElementById('editSectionLastNameInput').value = lastName;
    if (document.getElementById('editSectionEmailInput')) document.getElementById('editSectionEmailInput').value = userData.email || 'priya@gmail.com';
    if (document.getElementById('editSectionMobileInput')) document.getElementById('editSectionMobileInput').value = (userData.mobile || '9876543210').replace(/\D/g, '');
    if (document.getElementById('editSectionBusinessInput')) document.getElementById('editSectionBusinessInput').value = userData.business || 'Priya Aqua Wholesale';
    if (document.getElementById('editSectionAddressInput')) document.getElementById('editSectionAddressInput').value = userData.address || 'Plot 42, Ambattur Industrial Estate, Chennai - 600058';
  }

  // Global Profile Navigation & Section Trigger Helper
  window.openProfileOption = function(optionKey) {
    console.log('Opening profile option:', optionKey);
    let userData = {};
    try {
      userData = JSON.parse(localStorage.getItem('ro_b2b_user') || '{}');
    } catch (e) {}

    if (!userData.email) {
      userData = {
        email: 'priya@gmail.com',
        name: 'Priya Angel',
        owner: 'Priya Angel',
        mobile: '9876543210',
        business: 'Priya Aqua Wholesale',
        address: 'Plot 42, Ambattur Industrial Estate, Chennai - 600058'
      };
      localStorage.setItem('ro_b2b_user', JSON.stringify(userData));
    }

    switch (optionKey) {
      case 'edit':
        populateEditProfileForm(userData);
        if (document.getElementById('errEditName')) document.getElementById('errEditName').style.display = 'none';
        if (document.getElementById('errEditMobile')) document.getElementById('errEditMobile').style.display = 'none';
        if (document.getElementById('errEditSectionName')) document.getElementById('errEditSectionName').style.display = 'none';
        if (document.getElementById('errEditSectionMobile')) document.getElementById('errEditSectionMobile').style.display = 'none';
        navigateToScreen('edit-profile-tab');
        showCategoryToast('✏️ Opening Edit Profile section...');
        break;

      case 'orders':
        loadUserOrderHistory();
        navigateToScreen('my-orders-tab');
        showCategoryToast('📦 Opening My Orders & History section...');
        break;

      case 'rewards':
        loadUserRewardPoints();
        navigateToScreen('my-rewards-tab');
        showCategoryToast('⭐ Opening My Reward Points section...');
        break;

      case 'gst':
        loadUserGstInvoices();
        navigateToScreen('gst-invoices-tab');
        showCategoryToast('📄 Opening GST Invoices & Credit Limit section...');
        break;

      case 'addresses':
        loadUserAddresses();
        navigateToScreen('delivery-addresses-tab');
        showCategoryToast('📍 Opening Delivery Addresses section...');
        break;

      case 'password':
        document.getElementById('changePasswordForm')?.reset();
        document.getElementById('changePasswordSectionForm')?.reset();
        if (document.getElementById('errCurrentPass')) document.getElementById('errCurrentPass').style.display = 'none';
        if (document.getElementById('errNewPass')) document.getElementById('errNewPass').style.display = 'none';
        if (document.getElementById('errConfirmNewPass')) document.getElementById('errConfirmNewPass').style.display = 'none';
        if (document.getElementById('errSectionCurrentPass')) document.getElementById('errSectionCurrentPass').style.display = 'none';
        if (document.getElementById('errSectionNewPass')) document.getElementById('errSectionNewPass').style.display = 'none';
        if (document.getElementById('errSectionConfirmNewPass')) document.getElementById('errSectionConfirmNewPass').style.display = 'none';
        navigateToScreen('change-password-tab');
        showCategoryToast('🔑 Opening Change Password section...');
        break;

      case 'support':
        navigateToScreen('dealer-support-tab');
        showCategoryToast('🎧 Opening 24/7 Wholesale Support section...');
        break;

      case 'back':
        navigateToScreen('profile-tab');
        break;

      case 'logout':
        document.getElementById('btnLogoutApp')?.click();
        break;
    }
  };

  // Top-Right Header Profile Icon Button Click Handler
  document.getElementById('headerProfileBtn')?.addEventListener('click', () => {
    renderUserProfileData();
    navigateToScreen('profile-tab');
  });

  document.getElementById('btnBackFromProfileTab')?.addEventListener('click', () => {
    goBack();
  });

  // Universal Click Event Delegation for Profile Menu Rows (Entire row & arrow clickable)
  document.addEventListener('click', (e) => {
    const editBtn = e.target.closest('#profileEditBtn');
    if (editBtn) {
      e.preventDefault();
      e.stopPropagation();
      window.openProfileOption('edit');
      return;
    }

    const ordersBtn = e.target.closest('#profileMyOrdersBtn');
    if (ordersBtn) {
      e.preventDefault();
      e.stopPropagation();
      window.openProfileOption('orders');
      return;
    }

    const addrBtn = e.target.closest('#profileAddressesBtn');
    if (addrBtn) {
      e.preventDefault();
      e.stopPropagation();
      window.openProfileOption('addresses');
      return;
    }

    const rewardsBtn = e.target.closest('#profileRewardsBtn');
    if (rewardsBtn) {
      e.preventDefault();
      e.stopPropagation();
      window.openProfileOption('rewards');
      return;
    }

    const supportBtn = e.target.closest('#profileSupportBtn');
    if (supportBtn) {
      e.preventDefault();
      e.stopPropagation();
      window.openProfileOption('support');
      return;
    }
  });

  // ==========================================================================
  // 1. EDIT PROFILE FEATURE (MODAL & SECTION FORMS)
  // ==========================================================================
  document.getElementById('profileEditBtn')?.addEventListener('click', () => {
    window.openProfileOption('edit');
  });

  document.getElementById('closeEditProfileModal')?.addEventListener('click', () => {
    closeModal('editProfileModal');
  });

  async function handleProfileSaveSubmit(firstNameVal, lastNameVal, emailVal, mobileVal, businessVal, addressVal, saveBtn, errNameElem, errMobileElem) {
    const nameVal = `${firstNameVal} ${lastNameVal}`.trim();

    let hasError = false;
    if (!firstNameVal) {
      if (errNameElem) errNameElem.style.display = 'block';
      hasError = true;
    } else {
      if (errNameElem) errNameElem.style.display = 'none';
    }

    if (!mobileVal || mobileVal.length !== 10) {
      if (errMobileElem) errMobileElem.style.display = 'block';
      hasError = true;
    } else {
      if (errMobileElem) errMobileElem.style.display = 'none';
    }

    if (hasError) return;

    const origHTML = saveBtn ? saveBtn.innerHTML : '';
    if (saveBtn) {
      saveBtn.disabled = true;
      saveBtn.innerHTML = '<span>Saving...</span> <i class="fas fa-spinner fa-spin"></i>';
    }

    try {
      const res = await fetch('/api/user/update-profile', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: emailVal,
          name: nameVal,
          mobile: mobileVal,
          business: businessVal,
          address: addressVal
        })
      });

      const data = await res.json();
      if (saveBtn) {
        saveBtn.disabled = false;
        saveBtn.innerHTML = origHTML;
      }

      if (!res.ok || !data.success) {
        showCategoryToast(data.error || '❌ Failed to update profile.');
        return;
      }

      localStorage.setItem('ro_b2b_user', JSON.stringify(data.user));
      renderUserProfileData();
      closeModal('editProfileModal');
      showCategoryToast('🎉 Profile updated successfully!');
      setTimeout(() => {
        navigateToScreen('profile-tab');
      }, 600);
    } catch (err) {
      if (saveBtn) {
        saveBtn.disabled = false;
        saveBtn.innerHTML = origHTML;
      }
      showCategoryToast('❌ Network error updating profile.');
    }
  }

  document.getElementById('editProfileForm')?.addEventListener('submit', (e) => {
    e.preventDefault();
    handleProfileSaveSubmit(
      document.getElementById('editProfileFirstNameInput').value.trim(),
      document.getElementById('editProfileLastNameInput').value.trim(),
      document.getElementById('editProfileEmailInput').value.trim(),
      document.getElementById('editProfileMobileInput').value.replace(/\D/g, ''),
      document.getElementById('editProfileBusinessInput').value.trim(),
      document.getElementById('editProfileAddressInput').value.trim(),
      document.getElementById('btnSaveProfile'),
      document.getElementById('errEditName'),
      document.getElementById('errEditMobile')
    );
  });

  document.getElementById('editProfileSectionForm')?.addEventListener('submit', (e) => {
    e.preventDefault();
    handleProfileSaveSubmit(
      document.getElementById('editSectionFirstNameInput').value.trim(),
      document.getElementById('editSectionLastNameInput').value.trim(),
      document.getElementById('editSectionEmailInput').value.trim(),
      document.getElementById('editSectionMobileInput').value.replace(/\D/g, ''),
      document.getElementById('editSectionBusinessInput').value.trim(),
      document.getElementById('editSectionAddressInput').value.trim(),
      document.getElementById('btnSaveSectionProfile'),
      document.getElementById('errEditSectionName'),
      document.getElementById('errEditSectionMobile')
    );
  });

  // ==========================================================================
  // 2. CHANGE PASSWORD FEATURE (MIN 8 CHARACTERS VALIDATION)
  // ==========================================================================
  document.getElementById('profileChangePasswordBtn')?.addEventListener('click', () => {
    window.openProfileOption('password');
  });

  document.getElementById('closeChangePasswordModal')?.addEventListener('click', () => {
    closeModal('changePasswordModal');
  });

  async function handleChangePasswordSubmit(currentPass, newPass, confirmPass, saveBtn, errCurrentPass, errNewPass, errConfirmNewPass) {
    const userData = JSON.parse(localStorage.getItem('ro_b2b_user') || '{}');
    const email = userData.email || 'priya@gmail.com';

    let hasError = false;
    if (!currentPass) {
      if (errCurrentPass) errCurrentPass.style.display = 'block';
      hasError = true;
    } else {
      if (errCurrentPass) errCurrentPass.style.display = 'none';
    }

    if (!newPass || newPass.length < 8) {
      if (errNewPass) errNewPass.style.display = 'block';
      hasError = true;
    } else {
      if (errNewPass) errNewPass.style.display = 'none';
    }

    if (!confirmPass || confirmPass !== newPass) {
      if (errConfirmNewPass) errConfirmNewPass.style.display = 'block';
      hasError = true;
    } else {
      if (errConfirmNewPass) errConfirmNewPass.style.display = 'none';
    }

    if (hasError) return;

    const origHTML = saveBtn ? saveBtn.innerHTML : '';
    if (saveBtn) {
      saveBtn.disabled = true;
      saveBtn.innerHTML = '<span>Updating...</span> <i class="fas fa-spinner fa-spin"></i>';
    }

    try {
      const res = await fetch('/api/user/change-password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: email,
          currentPassword: currentPass,
          newPassword: newPass
        })
      });

      const data = await res.json();
      if (saveBtn) {
        saveBtn.disabled = false;
        saveBtn.innerHTML = origHTML;
      }

      if (!res.ok || !data.success) {
        showCategoryToast(data.error || '❌ Failed to change password.');
        return;
      }

      closeModal('changePasswordModal');
      showCategoryToast(data.message || '🎉 Password changed successfully!');
      setTimeout(() => {
        navigateToScreen('profile-tab');
      }, 600);
    } catch (err) {
      if (saveBtn) {
        saveBtn.disabled = false;
        saveBtn.innerHTML = origHTML;
      }
      showCategoryToast('❌ Network error changing password.');
    }
  }

  document.getElementById('changePasswordForm')?.addEventListener('submit', (e) => {
    e.preventDefault();
    handleChangePasswordSubmit(
      document.getElementById('currentPasswordInput').value.trim(),
      document.getElementById('newPasswordInput').value.trim(),
      document.getElementById('confirmNewPasswordInput').value.trim(),
      document.getElementById('btnSavePassword'),
      document.getElementById('errCurrentPass'),
      document.getElementById('errNewPass'),
      document.getElementById('errConfirmNewPass')
    );
  });

  document.getElementById('changePasswordSectionForm')?.addEventListener('submit', (e) => {
    e.preventDefault();
    handleChangePasswordSubmit(
      document.getElementById('currentPasswordSectionInput').value.trim(),
      document.getElementById('newPasswordSectionInput').value.trim(),
      document.getElementById('confirmNewPasswordSectionInput').value.trim(),
      document.getElementById('btnSavePasswordSection'),
      document.getElementById('errSectionCurrentPass'),
      document.getElementById('errSectionNewPass'),
      document.getElementById('errSectionConfirmNewPass')
    );
  });

  // ==========================================================================
  // 3. DELIVERY ADDRESSES MANAGEMENT (ADD, EDIT, DELETE, SELECT)
  // ==========================================================================
  // --------------------------------------------------------------------------
  // DYNAMIC MULTI-ADDRESS SYSTEM (SET DEFAULT & CHECKOUT ADDRESS SELECTOR)
  // --------------------------------------------------------------------------
  window.cachedUserAddresses = [];
  window.selectedCheckoutAddressId = null;

  async function loadCheckoutAddresses() {
    const selectorContainer = document.getElementById('checkoutAddressSelectorContainer');
    if (!selectorContainer) return;

    let userData = {};
    try {
      userData = JSON.parse(localStorage.getItem('ro_b2b_user') || '{}');
    } catch(e) {}
    const email = userData.email || '';

    if (!email) {
      selectorContainer.innerHTML = `<div style="color: #64748B; font-size: 12px; padding: 10px;">Please login to select a delivery address.</div>`;
      return;
    }

    try {
      const res = await fetch(`/api/user/addresses?email=${encodeURIComponent(email)}`);
      const data = await res.json();
      const addresses = (res.ok && data.success && Array.isArray(data.addresses)) ? data.addresses : [];
      window.cachedUserAddresses = addresses;

      if (addresses.length === 0) {
        selectorContainer.innerHTML = `
          <div style="background: #F8FAFC; border: 1px dashed #CBD5E1; padding: 14px; border-radius: 12px; text-align: center;">
            <div style="font-size: 12.5px; font-weight: 700; color: #1E293B;">No Saved Addresses Found</div>
            <button onclick="if(window.openProfileOption) window.openProfileOption('addresses')" style="margin-top: 8px; background: #0F62FE; color: white; border: none; padding: 6px 14px; border-radius: 10px; font-size: 11px; font-weight: 850; cursor: pointer;">
              + Add Delivery Address
            </button>
          </div>
        `;
        return;
      }

      if (!window.selectedCheckoutAddressId || !addresses.some(a => a.id === window.selectedCheckoutAddressId)) {
        const defAddr = addresses.find(a => a.isDefault) || addresses[0];
        window.selectedCheckoutAddressId = defAddr.id;
      }

      selectorContainer.innerHTML = addresses.map(addr => {
        const isSelected = (addr.id === window.selectedCheckoutAddressId);
        const typeStr = (addr.addressType || addr.label || 'Office').toUpperCase();

        return `
          <label class="checkout-address-card-label" style="display: flex; gap: 12px; padding: 14px; border: ${isSelected ? '2px solid #0F62FE' : '1.5px solid #CBD5E1'}; background: ${isSelected ? '#EFF6FF' : '#FFFFFF'}; border-radius: 16px; cursor: pointer; transition: all 0.2s ease; position: relative;">
            <input type="radio" name="checkoutAddressRadio" value="${addr.id}" ${isSelected ? 'checked' : ''} style="accent-color: #0F62FE; margin-top: 3px; width: 18px; height: 18px; cursor: pointer; flex-shrink: 0;">
            <div style="flex: 1;">
              <div style="display: flex; align-items: flex-start; justify-content: space-between; gap: 8px; margin-bottom: 4px;">
                <div style="font-size: 13.5px; font-weight: 850; color: #0F172A; line-height: 1.25;">
                  ${addr.fullName || userData.name || 'Recipient'} ${addr.businessName ? `<span style="font-size: 12px; font-weight: 600; color: #475569;">(${addr.businessName})</span>` : ''}
                </div>
                <div style="display: flex; gap: 6px; flex-shrink: 0; align-items: center;">
                  <span style="font-size: 9px; font-weight: 850; background: #E2E8F0; color: #475569; padding: 3px 8px; border-radius: 6px; text-transform: uppercase;">${typeStr}</span>
                  ${addr.isDefault ? '<span style="font-size: 9px; font-weight: 850; background: #0F62FE; color: white; padding: 3px 8px; border-radius: 6px; text-transform: uppercase; letter-spacing: 0.3px;">DEFAULT</span>' : ''}
                </div>
              </div>
              <div style="font-size: 12px; color: #475569; line-height: 1.4; margin-top: 4px; font-weight: 500;">
                ${addr.street}${addr.area ? ', ' + addr.area : ''}, ${addr.city}, ${addr.state || 'Tamil Nadu'} - <strong style="color: #0F172A;">${addr.pincode}</strong>
              </div>
              <div style="font-size: 11.5px; font-weight: 750; color: #0F62FE; margin-top: 6px;">Ph: +91 ${addr.phone}</div>
            </div>
          </label>
        `;
      }).join('');

      selectorContainer.querySelectorAll('input[name="checkoutAddressRadio"]').forEach(radio => {
        radio.addEventListener('change', () => {
          window.selectedCheckoutAddressId = radio.value;
          loadCheckoutAddresses();
        });
      });

    } catch (err) {
      selectorContainer.innerHTML = `<div style="color: #EF4444; font-size: 12px; padding: 10px;">Error loading saved addresses.</div>`;
    }
  }

  async function loadUserAddresses() {
    const userData = JSON.parse(localStorage.getItem('ro_b2b_user') || '{}');
    const email = userData.email || '';
    const container = document.getElementById('addressesListContainer');
    const sectionContainer = document.getElementById('sectionAddressesListContainer');

    if (!email) {
      const emptyMsg = `<div style="text-align: center; color: #64748B; padding: 20px;">Please login to view delivery addresses.</div>`;
      if (container) container.innerHTML = emptyMsg;
      if (sectionContainer) sectionContainer.innerHTML = emptyMsg;
      return;
    }

    try {
      const res = await fetch(`/api/user/addresses?email=${encodeURIComponent(email)}`);
      const data = await res.json();
      const addresses = (res.ok && data.success && Array.isArray(data.addresses)) ? data.addresses : [];
      window.cachedUserAddresses = addresses;

      const renderCards = (addrs) => {
        if (!addrs || addrs.length === 0) {
          return `
            <div style="text-align: center; padding: 36px 16px; color: #64748B; background: var(--bg-surface); border-radius: 18px; border: 1px solid var(--border-color);">
              <i class="fas fa-map-marked-alt" style="font-size: 38px; color: #CBD5E1; margin-bottom: 10px;"></i>
              <div style="font-size: 14px; font-weight: 850; color: #1E293B;">No Delivery Addresses Saved</div>
              <p style="font-size: 11.5px; margin-top: 4px; color: #64748B;">Click "+ Add New" to add a new delivery warehouse or office address.</p>
            </div>
          `;
        }

        return addrs.map(addr => {
          const typeStr = addr.addressType || addr.label || 'Office';
          const iconClass = typeStr === 'Office' ? 'fas fa-building' : (typeStr === 'Warehouse' ? 'fas fa-warehouse' : 'fas fa-map-marker-alt');
          const badgeBg = typeStr === 'Office' ? '#EFF6FF' : (typeStr === 'Warehouse' ? '#FEF3C7' : '#F1F5F9');
          const badgeColor = typeStr === 'Office' ? '#0F62FE' : (typeStr === 'Warehouse' ? '#D97706' : '#475569');

          return `
            <div class="address-item-card" style="border: ${addr.isDefault ? '2px solid #0F62FE' : '1px solid var(--border-color)'}; background: ${addr.isDefault ? '#F4F8FF' : 'var(--bg-surface)'}; padding: 14px; border-radius: 16px; position: relative; box-shadow: 0 4px 14px rgba(0,0,0,0.02); transition: all 0.2s ease;">
              
              <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;">
                <div style="display: flex; align-items: center; gap: 8px;">
                  <span style="background: ${badgeBg}; color: ${badgeColor}; font-size: 10px; font-weight: 850; padding: 3px 10px; border-radius: 8px; border: 1px solid rgba(0,0,0,0.06); text-transform: uppercase;">
                    <i class="${iconClass}" style="margin-right: 4px;"></i>
                    ${typeStr}
                  </span>
                  ${addr.isDefault ? '<span style="background: #0F62FE; color: #FFFFFF; font-size: 9.5px; font-weight: 850; padding: 2px 8px; border-radius: 10px; letter-spacing: 0.3px;">DEFAULT</span>' : ''}
                </div>
                ${addr.gstNumber ? `<span style="font-size: 10px; font-weight: 800; color: #059669; background: #D1FAE5; padding: 2px 8px; border-radius: 8px; border: 1px solid rgba(16,185,129,0.3);">GSTIN: ${addr.gstNumber}</span>` : ''}
              </div>

              <div style="font-size: 14.5px; font-weight: 850; color: #0F172A; margin-top: 2px;">
                ${addr.fullName || userData.name || 'Recipient'} 
                ${addr.businessName ? `<span style="font-size: 12px; font-weight: 600; color: #64748B; margin-left: 4px;">(${addr.businessName})</span>` : ''}
              </div>

              <div style="font-size: 12px; color: #334155; margin-top: 6px; line-height: 1.45; font-weight: 500;">
                ${addr.street}${addr.area ? ', ' + addr.area : ''}, ${addr.city}, ${addr.state || 'Tamil Nadu'} - <strong style="color: #0F172A;">${addr.pincode}</strong>
              </div>

              <div style="font-size: 11.5px; font-weight: 750; color: #0F62FE; margin-top: 8px; display: flex; align-items: center; gap: 6px;">
                <i class="fas fa-phone-alt" style="font-size: 10.5px;"></i> +91 ${addr.phone}
              </div>

              <div style="display: flex; gap: 8px; margin-top: 12px; border-top: 1px dashed var(--border-color); padding-top: 10px; justify-content: flex-end; align-items: center; flex-wrap: wrap;">
                ${!addr.isDefault ? `
                  <button class="btn-set-default-addr" data-id="${addr.id}" style="background: #F1F5F9; border: 1px solid #CBD5E1; color: #1E293B; font-size: 11px; font-weight: 800; padding: 5px 10px; border-radius: 8px; cursor: pointer; display: flex; align-items: center; gap: 4px;">
                    <i class="fas fa-check-circle" style="color: #0F62FE;"></i> Set as Default
                  </button>
                ` : ''}
                <button class="btn-edit-addr" data-id="${addr.id}" style="background: #EFF6FF; border: 1px solid rgba(15,98,254,0.3); color: #0F62FE; font-size: 11px; font-weight: 800; padding: 5px 10px; border-radius: 8px; cursor: pointer; display: flex; align-items: center; gap: 4px;">
                  <i class="fas fa-edit"></i> Edit
                </button>
                <button class="btn-delete-addr" data-id="${addr.id}" style="background: #FEF2F2; border: 1px solid #FECACA; color: #EF4444; font-size: 11px; font-weight: 800; padding: 5px 10px; border-radius: 8px; cursor: pointer; display: flex; align-items: center; gap: 4px;">
                  <i class="fas fa-trash-alt"></i> Delete
                </button>
              </div>
            </div>
          `;
        }).join('');
      };

      const htmlContent = renderCards(addresses);
      if (container) container.innerHTML = htmlContent;
      if (sectionContainer) sectionContainer.innerHTML = htmlContent;

      const bindAddressEvents = (targetElem) => {
        if (!targetElem) return;

        targetElem.querySelectorAll('.btn-set-default-addr').forEach(btn => {
          btn.addEventListener('click', async () => {
            const id = btn.getAttribute('data-id');
            try {
              const setRes = await fetch('/api/user/addresses/set-default', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email: email, addressId: id })
              });
              const setData = await setRes.json();
              if (setData.success) {
                showCategoryToast('📌 Set as Default Delivery Address!');
                loadUserAddresses();
              }
            } catch (e) {
              showCategoryToast('❌ Failed to update default address.');
            }
          });
        });

        targetElem.querySelectorAll('.btn-edit-addr').forEach(btn => {
          btn.addEventListener('click', () => {
            const id = btn.getAttribute('data-id');
            const target = addresses.find(a => a.id === id);
            if (target) {
              hideAddressErrors();
              document.getElementById('addressEditId').value = target.id;
              document.getElementById('addAddressModalTitle').textContent = 'Edit Delivery Address';
              document.getElementById('addrFullNameInput').value = target.fullName || userData.name || '';
              document.getElementById('addrPhoneInput').value = target.phone || userData.mobile || '';
              document.getElementById('addrBusinessNameInput').value = target.businessName || userData.business || '';
              document.getElementById('addrStreetInput').value = target.street || '';
              document.getElementById('addrAreaInput').value = target.area || '';
              document.getElementById('addrCityInput').value = target.city || '';
              document.getElementById('addrStateInput').value = target.state || 'Tamil Nadu';
              document.getElementById('addrPincodeInput').value = target.pincode || '';
              document.getElementById('addrGstInput').value = target.gstNumber || '';

              const typeVal = target.addressType || target.label || 'Office';
              const radioTarget = document.querySelector(`input[name="addrType"][value="${typeVal}"]`) || document.querySelector('input[name="addrType"][value="Office"]');
              if (radioTarget) radioTarget.checked = true;

              document.getElementById('addrIsDefaultCheck').checked = !!target.isDefault;

              openModal('addAddressModal');
            }
          });
        });

        targetElem.querySelectorAll('.btn-delete-addr').forEach(btn => {
          btn.addEventListener('click', async () => {
            const id = btn.getAttribute('data-id');
            if (confirm('Are you sure you want to delete this delivery address?')) {
              try {
                const delRes = await fetch('/api/user/addresses/delete', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({ email: email, addressId: id })
                });
                const delData = await delRes.json();
                if (delData.success) {
                  showCategoryToast('Address deleted successfully.');
                  loadUserAddresses();
                }
              } catch (e) {
                showCategoryToast('❌ Failed to delete address.');
              }
            }
          });
        });
      };

      bindAddressEvents(container);
      bindAddressEvents(sectionContainer);

    } catch (err) {
      const errMsg = `<div style="text-align: center; color: #EF4444; padding: 20px;">Error loading addresses.</div>`;
      if (container) container.innerHTML = errMsg;
      if (sectionContainer) sectionContainer.innerHTML = errMsg;
    }
  }

  function hideAddressErrors() {
    ['errAddrName', 'errAddrMobile', 'errAddrStreet', 'errAddrCity', 'errAddrState', 'errAddrPincode', 'errAddrGeneral'].forEach(id => {
      const el = document.getElementById(id);
      if (el) el.style.display = 'none';
    });
  }

  document.getElementById('profileAddressesBtn')?.addEventListener('click', () => {
    window.openProfileOption('addresses');
  });

  document.querySelectorAll('.btn-change-address').forEach(btn => {
    btn.addEventListener('click', () => {
      window.openProfileOption('addresses');
    });
  });

  document.getElementById('closeAddressModal')?.addEventListener('click', () => {
    closeModal('addressModal');
  });

  const triggerOpenAddAddress = () => {
    let userData = {};
    try {
      userData = JSON.parse(localStorage.getItem('ro_b2b_user') || '{}');
    } catch(e) {}

    const formElem = document.getElementById('addAddressForm');
    if (formElem) formElem.reset();

    const editIdInput = document.getElementById('addressEditId');
    if (editIdInput) editIdInput.value = '';

    const modalTitle = document.getElementById('addAddressModalTitle');
    if (modalTitle) modalTitle.textContent = 'Add New Delivery Address';

    const nameInput = document.getElementById('addrFullNameInput');
    if (nameInput) nameInput.value = userData.name || userData.owner || '';

    const phoneInput = document.getElementById('addrPhoneInput');
    if (phoneInput) phoneInput.value = userData.mobile || '';

    const busInput = document.getElementById('addrBusinessNameInput');
    if (busInput) busInput.value = userData.business || '';

    const stateInput = document.getElementById('addrStateInput');
    if (stateInput) stateInput.value = 'Tamil Nadu';
    
    const radioOffice = document.querySelector('input[name="addrType"][value="Office"]');
    if (radioOffice) radioOffice.checked = true;

    const defCheck = document.getElementById('addrIsDefaultCheck');
    if (defCheck) defCheck.checked = false;

    hideAddressErrors();
    openModal('addAddressModal');

    setTimeout(() => {
      if (nameInput) nameInput.focus();
    }, 100);
  };

  window.triggerOpenAddAddress = triggerOpenAddAddress;

  document.getElementById('btnOpenAddAddress')?.addEventListener('click', triggerOpenAddAddress);
  document.getElementById('btnSectionOpenAddAddress')?.addEventListener('click', triggerOpenAddAddress);

  document.addEventListener('click', (e) => {
    const addAddrBtn = e.target.closest('#btnSectionOpenAddAddress, #btnOpenAddAddress, .btn-open-add-address, .btn-section-open-add-address');
    if (addAddrBtn) {
      e.preventDefault();
      e.stopPropagation();
      triggerOpenAddAddress();
    }
  });

  document.getElementById('btnCancelAddAddress')?.addEventListener('click', () => {
    closeModal('addAddressModal');
  });

  document.getElementById('closeAddAddressModal')?.addEventListener('click', () => {
    closeModal('addAddressModal');
  });

  document.getElementById('btnCancelAddressForm')?.addEventListener('click', () => {
    closeModal('addAddressModal');
  });

  document.getElementById('addAddressForm')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    hideAddressErrors();

    const userData = JSON.parse(localStorage.getItem('ro_b2b_user') || '{}');
    const email = userData.email || '';
    if (!email) {
      showCategoryToast('⚠️ Please login to save address.');
      return;
    }

    const editId = document.getElementById('addressEditId').value.trim();
    const fullName = document.getElementById('addrFullNameInput').value.trim();
    const phone = document.getElementById('addrPhoneInput').value.replace(/\D/g, '').trim();
    const businessName = document.getElementById('addrBusinessNameInput').value.trim();
    const street = document.getElementById('addrStreetInput').value.trim();
    const area = document.getElementById('addrAreaInput').value.trim();
    const city = document.getElementById('addrCityInput').value.trim();
    const state = document.getElementById('addrStateInput').value.trim();
    const pincode = document.getElementById('addrPincodeInput').value.replace(/\D/g, '').trim();
    const gstNumber = document.getElementById('addrGstInput').value.trim().toUpperCase();
    const typeRadio = document.querySelector('input[name="addrType"]:checked');
    const addressType = typeRadio ? typeRadio.value : 'Office';
    const isDefault = document.getElementById('addrIsDefaultCheck').checked;

    let hasError = false;

    if (!fullName) {
      const errName = document.getElementById('errAddrName');
      if (errName) errName.style.display = 'block';
      hasError = true;
    }

    if (!phone || phone.length !== 10) {
      const errMobile = document.getElementById('errAddrMobile');
      if (errMobile) errMobile.style.display = 'block';
      hasError = true;
    }

    if (!street) {
      const errStreet = document.getElementById('errAddrStreet');
      if (errStreet) errStreet.style.display = 'block';
      hasError = true;
    }

    if (!city) {
      const errCity = document.getElementById('errAddrCity');
      if (errCity) errCity.style.display = 'block';
      hasError = true;
    }

    if (!state) {
      const errState = document.getElementById('errAddrState');
      if (errState) errState.style.display = 'block';
      hasError = true;
    }

    if (!pincode || pincode.length !== 6) {
      const errPincode = document.getElementById('errAddrPincode');
      if (errPincode) errPincode.style.display = 'block';
      hasError = true;
    }

    if (hasError) return;

    const saveBtn = document.getElementById('btnSaveAddressSubmit');
    const origBtnHTML = saveBtn ? saveBtn.innerHTML : 'Save Address';
    if (saveBtn) {
      saveBtn.disabled = true;
      saveBtn.innerHTML = '<span>Saving...</span> <i class="fas fa-spinner fa-spin"></i>';
    }

    try {
      const res = await fetch('/api/user/addresses/save', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: email,
          id: editId || undefined,
          fullName: fullName,
          phone: phone,
          businessName: businessName || `${fullName} Wholesale`,
          street: street,
          area: area,
          city: city,
          state: state || 'Tamil Nadu',
          pincode: pincode,
          gstNumber: gstNumber,
          addressType: addressType,
          label: addressType,
          isDefault: isDefault
        })
      });

      const data = await res.json();
      if (saveBtn) {
        saveBtn.disabled = false;
        saveBtn.innerHTML = origBtnHTML;
      }

      if (!res.ok || !data.success) {
        showCategoryToast(data.error || '❌ Failed to save address.');
        return;
      }

      closeModal('addAddressModal');
      showCategoryToast('🎉 Delivery address saved successfully!');
      await loadUserAddresses();
      await loadCheckoutAddresses();
    } catch (err) {
      if (saveBtn) {
        saveBtn.disabled = false;
        saveBtn.innerHTML = origBtnHTML;
      }
      showCategoryToast('❌ Network error saving address.');
    }
  });

  // ==========================================================================
  // 4. MY ORDERS & ORDER HISTORY FEATURE (DYNAMIC PER USER ACCOUNT)
  // ==========================================================================
  // Helper: Format Order ISO Date cleanly
  function formatOrderDate(dateStr) {
    if (!dateStr) return 'Recent Order';
    try {
      const d = new Date(dateStr);
      if (isNaN(d.getTime())) return dateStr;
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      const day = String(d.getDate()).padStart(2, '0');
      const month = months[d.getMonth()];
      const year = d.getFullYear();
      let hours = d.getHours();
      const minutes = String(d.getMinutes()).padStart(2, '0');
      const ampm = hours >= 12 ? 'PM' : 'AM';
      hours = hours % 12;
      hours = hours ? hours : 12;
      const formattedHours = String(hours).padStart(2, '0');
      return `${day} ${month} ${year}, ${formattedHours}:${minutes} ${ampm}`;
    } catch (e) {
      return dateStr;
    }
  }

  // Render individual Order Card HTML cleanly
  function renderOrderCardHTML(ord) {
    const isDelivered = (ord.status || '').toLowerCase().includes('deliver');
    const statusBg = isDelivered ? '#D1FAE5' : '#EFF6FF';
    const statusColor = isDelivered ? '#059669' : '#0F62FE';
    const statusBorder = isDelivered ? 'rgba(16,185,129,0.3)' : 'rgba(15,98,254,0.3)';
    const statusText = ord.status || 'Processing & Dispatched';

    const itemsSummary = (ord.items || []).map(i => `${i.name} (x${i.quantity})`).join(', ') || 'RO Purifier Components';

    return `
      <div class="order-history-card" style="background: var(--bg-surface); border: 1px solid var(--border-color); border-radius: 18px; padding: 16px; box-shadow: 0 4px 14px rgba(0,0,0,0.02); transition: all 0.2s ease;">
        
        <!-- Header Row: Order ID, Date & Status Badge -->
        <div style="display: flex; justify-content: space-between; align-items: flex-start; gap: 10px; border-bottom: 1px dashed var(--border-color); padding-bottom: 10px; margin-bottom: 10px;">
          <div style="flex: 1; min-width: 0;">
            <div style="font-size: 13.5px; font-weight: 900; color: #0F172A; word-break: break-word; line-height: 1.25;">
              Order ${ord.orderId}
            </div>
            <div style="font-size: 11px; color: #64748B; margin-top: 3px; font-weight: 500; display: flex; align-items: center; gap: 4px;">
              <i class="far fa-calendar-alt" style="color: #0F62FE; font-size: 10.5px;"></i>
              <span>Date: ${formatOrderDate(ord.createdAt || ord.date)}</span>
            </div>
          </div>
          <span style="font-size: 9.5px; font-weight: 850; padding: 4px 10px; border-radius: 10px; text-transform: uppercase; white-space: nowrap; flex-shrink: 0; background: ${statusBg}; color: ${statusColor}; border: 1px solid ${statusBorder}; letter-spacing: 0.3px;">
            ${statusText}
          </span>
        </div>

        <!-- Purchased Items Summary -->
        <div style="font-size: 12.5px; font-weight: 700; color: #1E293B; margin-bottom: 8px; display: flex; align-items: flex-start; gap: 6px; line-height: 1.35;">
          <i class="fas fa-box" style="color: #0F62FE; font-size: 11px; margin-top: 3px; flex-shrink: 0;"></i>
          <span>${itemsSummary}</span>
        </div>

        <!-- Delivery Address Container -->
        <div style="font-size: 11.5px; color: #334155; margin-bottom: 10px; background: #F8FAFC; padding: 10px 12px; border-radius: 12px; border: 1px solid #E2E8F0; line-height: 1.45; word-break: break-word;">
          <div style="font-size: 10.5px; font-weight: 800; color: #0F62FE; text-transform: uppercase; margin-bottom: 3px; display: flex; align-items: center; gap: 4px;">
            <i class="fas fa-map-marker-alt"></i> Delivery Address
          </div>
          <span style="font-weight: 500;">${ord.deliveryAddress || 'Standard Delivery Hub'}</span>
        </div>

        <!-- Footer Row: Payment Method, Total Amount & Track Order Button -->
        <div style="display: flex; justify-content: space-between; align-items: center; gap: 10px; margin-top: 10px; padding-top: 10px; border-top: 1px dashed var(--border-color); flex-wrap: wrap;">
          <div style="flex: 1; min-width: 0;">
            <div style="font-size: 10.5px; font-weight: 600; color: #64748B;">Payment: <span style="color: #334155; font-weight: 700;">${ord.paymentMethod || 'B2B Credit'}</span></div>
            <div style="font-size: 15px; font-weight: 900; color: #0F62FE; margin-top: 2px;">Total: ₹${(ord.grandTotal || ord.total || 0).toLocaleString('en-IN')}</div>
          </div>
          <button onclick="showCategoryToast('🚚 Order ${ord.orderId} status: ${ord.status || 'Processing & Dispatched'}')" style="background: #F8FAFC; border: 1.5px solid #CBD5E1; color: #0F172A; font-size: 11.5px; font-weight: 850; padding: 7px 14px; border-radius: 12px; cursor: pointer; white-space: nowrap; flex-shrink: 0; box-shadow: 0 2px 6px rgba(0,0,0,0.03); transition: all 0.2s ease;">
            Track Order
          </button>
        </div>

      </div>
    `;
  }

  function renderFilteredOrders(filterKey = 'all') {
    const container = document.getElementById('sectionOrderHistoryContainer');
    if (!container || !window.userOrderHistoryData) return;

    let orders = window.userOrderHistoryData || [];
    if (filterKey === 'processing') {
      orders = orders.filter(o => (o.status || '').toLowerCase().includes('process') || (o.status || '').toLowerCase().includes('dispatch'));
    } else if (filterKey === 'delivered') {
      orders = orders.filter(o => (o.status || '').toLowerCase().includes('deliver'));
    }

    if (orders.length === 0) {
      container.innerHTML = `
        <div style="background: var(--bg-surface); padding: 32px 16px; border-radius: 18px; border: 1px solid var(--border-color); text-align: center;">
          <i class="fas fa-filter" style="font-size: 32px; color: #CBD5E1; margin-bottom: 8px; display: block;"></i>
          <h4 style="font-size: 14px; font-weight: 850; color: #1E293B; margin-bottom: 4px;">No ${filterKey} orders found</h4>
          <p style="font-size: 11px; color: #64748B;">Select "All Orders" to view your complete order history.</p>
        </div>
      `;
      return;
    }

    container.innerHTML = orders.map(ord => renderOrderCardHTML(ord)).join('');
  }

  async function loadUserOrderHistory() {
    let userData = {};
    try {
      userData = JSON.parse(localStorage.getItem('ro_b2b_user') || '{}');
    } catch(e) {}
    const email = userData.email || 'priya@gmail.com';
    const container = document.getElementById('sectionOrderHistoryContainer');

    if (!container) return;
    container.innerHTML = `<div style="text-align: center; color: #64748B; padding: 20px;"><i class="fas fa-spinner fa-spin"></i> Loading order history...</div>`;

    try {
      const res = await fetch(`/api/user/orders?email=${encodeURIComponent(email)}`);
      const data = await res.json();
      const orders = data.orders || [];

      window.userOrderHistoryData = orders;

      if (orders.length === 0) {
        container.innerHTML = `
          <div style="background: var(--bg-surface); padding: 36px 20px; border-radius: 20px; border: 1px solid var(--border-color); text-align: center;">
            <div style="font-size: 38px; color: #CBD5E1; margin-bottom: 10px;"><i class="fas fa-box-open"></i></div>
            <h4 style="font-size: 15px; font-weight: 850; color: #1E293B; margin-bottom: 4px;">No Orders Placed Yet</h4>
            <p style="font-size: 11.5px; color: #64748B; margin-bottom: 16px;">Your wholesale orders will appear here with live tracking & status.</p>
            <button onclick="navigateToScreen('products-tab')" style="background: #0F62FE; color: white; border: none; padding: 10px 20px; border-radius: 20px; font-size: 12px; font-weight: 850; cursor: pointer;">Browse Wholesale Catalog</button>
          </div>
        `;
        return;
      }

      // Reset filter pills to All Orders when loading
      document.querySelectorAll('.order-filter-pill').forEach(p => {
        if (p.getAttribute('data-filter') === 'all') {
          p.classList.add('active');
          p.style.background = '#0F62FE';
          p.style.color = '#FFFFFF';
          p.style.border = 'none';
        } else {
          p.classList.remove('active');
          p.style.background = '#F1F5F9';
          p.style.color = '#475569';
          p.style.border = '1px solid #CBD5E1';
        }
      });

      container.innerHTML = orders.map(ord => renderOrderCardHTML(ord)).join('');

    } catch (err) {
      container.innerHTML = `<div style="text-align: center; color: #EF4444; padding: 20px;">Error loading order history.</div>`;
    }
  }

  // Attach click listener to order filter pills
  document.querySelectorAll('.order-filter-pill').forEach(pill => {
    pill.addEventListener('click', () => {
      document.querySelectorAll('.order-filter-pill').forEach(p => {
        p.classList.remove('active');
        p.style.background = '#F1F5F9';
        p.style.color = '#475569';
        p.style.border = '1px solid #CBD5E1';
      });
      pill.classList.add('active');
      pill.style.background = '#0F62FE';
      pill.style.color = '#FFFFFF';
      pill.style.border = 'none';

      const filter = pill.getAttribute('data-filter') || 'all';
      renderFilteredOrders(filter);
    });
  });
  window.loadUserOrderHistory = loadUserOrderHistory;

  document.getElementById('profileMyOrdersBtn')?.addEventListener('click', async () => {
    window.openProfileOption('orders');
  });

  // Update checkout order placement to send order data to backend DB
  const origCheckoutBtn = document.getElementById('btnContinueToPayment');
  if (origCheckoutBtn) {
    const newCheckoutBtn = origCheckoutBtn.cloneNode(true);
    origCheckoutBtn.parentNode.replaceChild(newCheckoutBtn, origCheckoutBtn);

    newCheckoutBtn.addEventListener('click', async () => {
      let userData = {};
      try {
        userData = JSON.parse(localStorage.getItem('ro_b2b_user') || '{}');
      } catch(e) {}
      const email = userData.email || 'priya@gmail.com';

      if (cartState.length === 0) {
        showCategoryToast('⚠️ Your cart is empty.');
        navigateToScreen('products-tab');
        return;
      }

      let subtotal = cartState.reduce((sum, item) => sum + (item.numericPrice * item.quantity), 0);
      let discount = Math.round(subtotal * 0.10);
      let gst = Math.round((subtotal - discount) * 0.18);
      let delivery = subtotal > 5000 ? 0 : 250;
      let grandTotal = (subtotal - discount) + gst + delivery;

      const payMethodElem = document.querySelector('input[name="payMethod"]:checked');
      const payMethod = payMethodElem ? payMethodElem.value : 'upi';
      const noteInput = document.getElementById('deliveryNoteInput');
      const note = noteInput ? noteInput.value.trim() : '';

      // Determine selected delivery address object
      let selectedAddrObj = null;
      if (window.cachedUserAddresses && window.cachedUserAddresses.length > 0) {
        selectedAddrObj = window.cachedUserAddresses.find(a => a.id === window.selectedCheckoutAddressId) || window.cachedUserAddresses.find(a => a.isDefault) || window.cachedUserAddresses[0];
      }

      let formattedDeliveryAddr = userData.address || 'Salem Main Road';
      if (selectedAddrObj) {
        formattedDeliveryAddr = `${selectedAddrObj.fullName || userData.name} (${selectedAddrObj.businessName || 'Aqua Wholesale'}), ${selectedAddrObj.street}${selectedAddrObj.area ? ', ' + selectedAddrObj.area : ''}, ${selectedAddrObj.city}, ${selectedAddrObj.state || 'Tamil Nadu'} - ${selectedAddrObj.pincode} (Ph: ${selectedAddrObj.phone})`;
      }

      newCheckoutBtn.disabled = true;
      newCheckoutBtn.innerHTML = '<span>Placing B2B Order...</span> <i class="fas fa-spinner fa-spin"></i>';

      try {
        const res = await fetch('/api/user/orders/create', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email: email,
            items: cartState,
            subtotal: subtotal,
            discount: discount,
            gst: gst,
            deliveryFee: delivery,
            grandTotal: grandTotal,
            paymentMethod: payMethod === 'credit' ? 'B2B Credit (15 Days)' : (payMethod === 'cod' ? 'Cash on Delivery (COD)' : 'UPI Direct QR Transfer'),
            deliveryAddress: formattedDeliveryAddr,
            deliveryNote: note
          })
        });

        const data = await res.json();
        newCheckoutBtn.disabled = false;
        newCheckoutBtn.innerHTML = 'Continue to Payment';

        if (!res.ok || !data.success) {
          showCategoryToast(data.error || '❌ Failed to place order.');
          return;
        }

        cartState = [];
        updateCartUI();
        const ptsCredited = typeof data.pointsEarned === 'number' ? data.pointsEarned : Math.floor(grandTotal / 100) * 5;
        showCategoryToast(`🎉 Order ${data.order.orderId} Placed! 🎉 ${ptsCredited} Reward Points added successfully!`);
        loadUserRewardPoints();
        setTimeout(() => {
          window.openProfileOption('rewards');
        }, 1400);
      } catch (err) {
        newCheckoutBtn.disabled = false;
        newCheckoutBtn.innerHTML = 'Continue to Payment';
        showCategoryToast('❌ Network error placing order.');
      }
    });
  }

  // ==========================================================================
  // 5. GST INVOICES & CREDIT LIMIT FEATURE (DYNAMIC PER USER ACCOUNT)
  // ==========================================================================
  async function loadUserGstInvoices() {
    let userData = {};
    try {
      userData = JSON.parse(localStorage.getItem('ro_b2b_user') || '{}');
    } catch(e) {}
    const email = userData.email || 'priya@gmail.com';
    const container = document.getElementById('sectionGstInvoicesContainer');
    const modalContainer = document.getElementById('gstInvoicesListContainer');
    const creditElem = document.getElementById('gstCreditLimitValue');
    const availElem = document.getElementById('gstAvailableCreditValue');
    const secCreditElem = document.getElementById('sectionGstCreditLimitValue');
    const secAvailElem = document.getElementById('sectionGstAvailableCreditValue');

    try {
      const res = await fetch(`/api/user/gst-invoices?email=${encodeURIComponent(email)}`);
      const data = await res.json();

      const creditStr = `₹${(data.creditLimit || 250000).toLocaleString()}`;
      const availStr = `Available Credit: ₹${(data.availableCredit || 250000).toLocaleString()} (15-Day Interest Free)`;

      if (creditElem) creditElem.textContent = creditStr;
      if (availElem) availElem.textContent = availStr;
      if (secCreditElem) secCreditElem.textContent = creditStr;
      if (secAvailElem) secAvailElem.textContent = availStr;

      const invoices = data.invoices || [];

      const renderInvHTML = (invs) => {
        if (invs.length === 0) {
          return `
            <div style="text-align: center; padding: 30px 16px; color: #64748B; background: var(--bg-surface); border-radius: 16px; border: 1px solid var(--border-color);">
              <i class="fas fa-file-invoice" style="font-size: 36px; color: #CBD5E1; margin-bottom: 8px;"></i>
              <div style="font-size: 13px; font-weight: 700; color: #1E293B;">No Invoices Generated Yet</div>
              <p style="font-size: 11px; margin-top: 4px;">B2B GST Tax Invoices will appear here automatically when you place wholesale orders.</p>
            </div>
          `;
        }
        return invs.map(inv => `
          <div style="background: var(--bg-surface); border: 1px solid var(--border-color); padding: 14px; border-radius: 14px; display: flex; align-items: center; justify-content: space-between;">
            <div>
              <div style="font-size: 13.5px; font-weight: 850; color: #0F172A;">${inv.invoiceNumber} (${inv.itemsSummary})</div>
              <div style="font-size: 11px; color: #64748B; margin-top: 2px;">Date: ${inv.date} • Total: ₹${(inv.amount || 0).toLocaleString()} (GST: ₹${(inv.gstAmount || 0).toLocaleString()})</div>
            </div>
            <button class="btn-download-inv" data-inv="${inv.invoiceNumber}" style="background: #EFF6FF; border: 1px solid rgba(15,98,254,0.3); color: #0F62FE; padding: 6px 12px; border-radius: 10px; font-size: 11px; font-weight: 850; cursor: pointer;">PDF</button>
          </div>
        `).join('');
      };

      const html = renderInvHTML(invoices);
      if (container) container.innerHTML = html;
      if (modalContainer) modalContainer.innerHTML = html;

      document.querySelectorAll('.btn-download-inv').forEach(btn => {
        btn.addEventListener('click', (e) => {
          e.stopPropagation();
          const num = btn.getAttribute('data-inv');
          showCategoryToast(`📥 Downloading GST Tax Invoice ${num} PDF...`);
        });
      });

    } catch (err) {
      if (container) container.innerHTML = `<div style="text-align: center; color: #EF4444; padding: 20px;">Error loading GST invoices.</div>`;
    }
  }

  document.getElementById('profileGstInvoicesBtn')?.addEventListener('click', () => {
    window.openProfileOption('gst');
  });

  document.getElementById('closeGstModal')?.addEventListener('click', () => {
    closeModal('gstInvoicesModal');
  });

  // ==========================================================================
  // 6. WHOLESALE DEALER SUPPORT FEATURE (CALL, WHATSAPP, RAISE TICKET)
  // ==========================================================================
  document.getElementById('profileSupportBtn')?.addEventListener('click', () => {
    window.openProfileOption('support');
  });
  document.getElementById('closeSupportModal')?.addEventListener('click', () => {
    closeModal('supportModal');
  });

  const triggerCallSupport = () => {
    showCategoryToast('📞 Connecting to Priority Dealer Helpline (+91 1800 200 4888)...');
    window.open('tel:18002004888');
  };

  const triggerChatSupport = () => {
    showCategoryToast('💬 Opening WhatsApp B2B Dealer Support Desk...');
    window.open('https://wa.me/919876543210?text=Hello%20RO%20Wholesale%20Support%2C%20I%20need%20assistance');
  };

  document.getElementById('btnCallSupport')?.addEventListener('click', triggerCallSupport);
  document.getElementById('btnCallSupportSection')?.addEventListener('click', triggerCallSupport);

  document.getElementById('btnChatSupport')?.addEventListener('click', triggerChatSupport);
  document.getElementById('btnChatSupportSection')?.addEventListener('click', triggerChatSupport);

  async function handleSupportTicketSubmit(subject, message, ticketBtn, formElem) {
    let userData = {};
    try {
      userData = JSON.parse(localStorage.getItem('ro_b2b_user') || '{}');
    } catch(e) {}
    const email = userData.email || 'priya@gmail.com';

    if (!message) {
      showCategoryToast('⚠️ Please describe your issue before submitting.');
      return;
    }

    if (ticketBtn) {
      ticketBtn.disabled = true;
      ticketBtn.innerHTML = '<span>Submitting Ticket...</span>';
    }

    try {
      const res = await fetch('/api/user/support-ticket', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: email,
          name: userData.name || userData.owner || 'Priya Angel',
          subject: subject || 'General Dealer Inquiry',
          message: message
        })
      });

      const data = await res.json();
      if (ticketBtn) {
        ticketBtn.disabled = false;
        ticketBtn.innerHTML = 'Submit Support Ticket';
      }

      if (!res.ok || !data.success) {
        showCategoryToast(data.error || '❌ Failed to submit support ticket.');
        return;
      }

      if (formElem) formElem.reset();
      showCategoryToast(data.message || '🎉 Support ticket submitted!');
      setTimeout(() => {
        navigateToScreen('profile-tab');
      }, 800);
    } catch (err) {
      if (ticketBtn) {
        ticketBtn.disabled = false;
        ticketBtn.innerHTML = 'Submit Support Ticket';
      }
      showCategoryToast('❌ Network error submitting ticket.');
    }
  }

  document.getElementById('supportTicketForm')?.addEventListener('submit', (e) => {
    e.preventDefault();
    handleSupportTicketSubmit(
      document.getElementById('supportSubjectInput').value.trim(),
      document.getElementById('supportMessageInput').value.trim(),
      document.getElementById('btnSubmitSupportTicket'),
      document.getElementById('supportTicketForm')
    );
  });

  document.getElementById('supportTicketSectionForm')?.addEventListener('submit', (e) => {
    e.preventDefault();
    handleSupportTicketSubmit(
      document.getElementById('supportSubjectSectionInput').value.trim(),
      document.getElementById('supportMessageSectionInput').value.trim(),
      document.getElementById('btnSubmitSupportTicketSection'),
      document.getElementById('supportTicketSectionForm')
    );
  });

  // 7. Hero Section Explore Button & Slider Indicators
  document.querySelector('.btn-explore')?.addEventListener('click', () => {
    showCategoryToast('Exploring Wholesale Products');
    navigateToScreen('products-tab');
  });
  document.querySelectorAll('.slider-indicators .indicator-dot').forEach((dot, idx) => {
    dot.addEventListener('click', () => {
      document.querySelectorAll('.slider-indicators .indicator-dot').forEach(d => d.classList.remove('active'));
      dot.classList.add('active');
      showCategoryToast(`Hero Slide ${idx + 1}`);
    });
  });

  // 8. Square Filter Button in Search Bar
  document.querySelector('.filter-btn-square')?.addEventListener('click', () => {
    showCategoryToast('Opening Wholesale Catalog Filters...');
    navigateToScreen('products-tab');
  });

  // 9. Quick Action Metric Cards
  document.querySelectorAll('.metric-action-card').forEach((card, idx) => {
    card.addEventListener('click', () => {
      const titles = ['100% Original Guaranteed', 'Bulk Order Tier Discounts', 'Express Delivery Active', '24/7 Dealer Support Desk'];
      showCategoryToast(`✓ ${titles[idx] || 'B2B Feature'}`);
    });
  });

  // 10. Wishlist Heart Button Handler Across All Product Cards
  document.addEventListener('click', (e) => {
    const heartBtn = e.target.closest('.heart-btn, .pearl-wishlist-btn');
    if (heartBtn) {
      e.preventDefault();
      e.stopPropagation();
      const isActive = heartBtn.classList.toggle('active');
      if (isActive) {
        heartBtn.style.color = '#FF4757';
        heartBtn.style.fill = '#FF4757';
        showCategoryToast('❤️ Added to Dealer Wishlist');
      } else {
        heartBtn.style.color = '';
        heartBtn.style.fill = '';
        showCategoryToast('Removed from Wishlist');
      }
    }
  });

  // 11. Modal Backdrop Click Handler
  document.querySelectorAll('.product-modal-overlay').forEach(modal => {
    modal.addEventListener('click', (e) => {
      if (e.target === modal) {
        modal.style.display = 'none';
        document.body.style.overflow = '';
      }
    });
  });

  // Initialize UI state on load: Ensure http://localhost:8080/ always displays Initial/Welcome Page first
  renderCatalogProducts('all');
  updateCartUI();

  const currentHash = window.location.hash.replace('#', '');
  if (!currentHash || currentHash === 'screen-splash' || currentHash === '') {
    history.replaceState({ screen: 'screen-splash' }, '', window.location.pathname);
    navigateToScreen('screen-splash', false);
  } else {
    navigateToScreen(currentHash, false);
  }
});
