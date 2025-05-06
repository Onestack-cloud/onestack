// The public key can be found in the Stripe Dashboard
const stripe = Stripe('pk_test_51P78jNFzZpjdOGbNf2cC0293N6PcRlU5DxOV1Ho5LgW6hEHB6g51cPprtYshWrpgQPQXQfgDEx8ogHRCWlvCN0Sp00IshzsYBC', { betas: ['custom_checkout_beta_5'] })

export const InitCheckout = {
    mounted() {
        console.log("InitCheckout hook mounted", this.el);
        console.log("Dataset secret:", this.el.dataset.secret);
        const successCallback = paymentIntent => { this.pushEvent('payment-success', paymentIntent) }
        init(this.el, successCallback)
    }
}

const init = async (form, successCallback) => {
    const clientSecret = form.dataset.secret
    if (!clientSecret) {
        console.error("No client secret found in dataset");
        return;
    }

    // Function to check if dark mode is active - first checks for data-theme attribute, then system preference
    const isDarkMode = () => {
        // Check if document has a theme attribute - this allows more control if you implement theme toggle
        const htmlElement = document.documentElement;
        if (htmlElement.dataset.theme) {
            return htmlElement.dataset.theme === 'dark';
        }

        // Fall back to system preference
        return window.matchMedia('(prefers-color-scheme: dark)').matches;
    };

    // Function to create appearance config based on current theme
    const createAppearance = (darkMode) => {
        return {
            theme: darkMode ? 'night' : 'stripe',
            labels: "floating",
            variables: {
                colorPrimary: '#0066FF',
                colorBackground: darkMode ? '#1F2937' : '#FFFFFF',
                colorText: darkMode ? '#F9FAFB' : '#1F2937',
                colorDanger: '#EF4444',
                fontFamily: '"Helvetica Neue", Helvetica, sans-serif',
                spacingUnit: '4px',
                borderRadius: '8px',
            },
            rules: {
                '.Input': {
                    color: darkMode ? '#F9FAFB' : '#1F2937',
                    backgroundColor: darkMode ? '#374151' : '#F9FAFB',
                    boxShadow: 'none',
                    border: darkMode ? '1px solid #4B5563' : '1px solid #D1D5DB',
                },
                '.Input:focus': {
                    border: darkMode ? '1px solid #60A5FA' : '1px solid #2563EB',
                    boxShadow: darkMode ? '0 0 0 1px #60A5FA' : '0 0 0 1px #93C5FD',
                },
                '.Label': {
                    color: darkMode ? '#D1D5DB' : '#4B5563',
                },
                '.Tab': {
                    color: darkMode ? '#D1D5DB' : '#4B5563',
                    borderColor: darkMode ? '#4B5563' : '#D1D5DB',
                },
                '.Tab:hover': {
                    color: darkMode ? '#F9FAFB' : '#1F2937',
                },
                '.Tab--selected': {
                    color: darkMode ? '#F9FAFB' : '#1F2937',
                    borderColor: darkMode ? '#60A5FA' : '#2563EB',
                },
                '.CheckboxInput': {
                    backgroundColor: darkMode ? '#374151' : '#F9FAFB',
                    borderColor: darkMode ? '#4B5563' : '#D1D5DB',
                },
                '.CheckboxInput--checked': {
                    backgroundColor: darkMode ? '#3B82F6' : '#2563EB',
                }
            }
        };
    };

    // Get initial appearance based on current theme
    const appearance = createAppearance(isDarkMode());

    const darkMode = isDarkMode();

    // Listen for theme changes
    const themeChangeListener = () => {
        const newDarkMode = isDarkMode();
    };

    // Listen for system preference changes
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', themeChangeListener);

    stripe.initCheckout({ clientSecret, elementsOptions: { appearance } }).then((checkout) => {
        const errors = document.getElementById('confirm-errors');

        // Configure payment element with explicit options
        const paymentElementOptions = {
            layout: 'tabs',
        };

        console.log("Creating payment element with options:", paymentElementOptions);
        const paymentElement = checkout.createElement('payment', paymentElementOptions);

        // We'll still use the address element for shipping/billing if needed
        const billingAddressElement = checkout.createElement('address', {
            mode: 'billing'
        });

        // Add change event listener to monitor payment element completeness
        let paymentElementComplete = false;
        paymentElement.on('change', (event) => {
            console.log('Payment element change event:', event);
            paymentElementComplete = event.complete;

            if (event.error) {
                console.log('Payment element error:', event.error.message);
                errors.textContent = event.error.message;
            } else {
                // Clear errors when fixed
                errors.textContent = '';
            }
        });

        // Ensure the confirm-errors element is properly styled
        if (errors) {
            errors.style.color = darkMode ? '#FCA5A5' : '#EF4444';
            errors.style.fontSize = '14px';
            errors.style.marginTop = '8px';
            errors.style.marginBottom = '0';
        }

        const button = document.getElementById('pay-button');
        if (button) {
            button.style.backgroundColor = darkMode ? '#3B82F6' : '#2563EB';
            button.style.color = '#FFFFFF';
            button.style.borderRadius = '8px';
            button.style.padding = '10px 16px';
            button.style.border = 'none';
            button.style.cursor = 'pointer';
            button.style.fontSize = '16px';
            button.style.fontWeight = '500';
        }

        button.addEventListener('click', (e) => {
            e.preventDefault();
            console.log("Payment button clicked");

            // Clear any validation errors
            errors.textContent = '';

            // Check if payment element is complete
            console.log("Payment element complete status:", paymentElementComplete);
            if (!paymentElementComplete) {
                console.log("Payment element is incomplete, cannot proceed");
                errors.textContent = 'Please fill in all required payment information.';
                return;
            }

            // Show loading state
            button.disabled = true;
            button.textContent = 'Processing...';
            button.style.backgroundColor = darkMode ? '#60A5FA' : '#93C5FD';

            checkout.confirm()
                .then(result => {
                    console.log("Checkout confirmation complete:", result);

                    if (result.error || result.type === 'error') {
                        const error = result.error || (result.type === 'error' ? result : null);
                        console.error("Payment error:", error);
                        errors.textContent = error?.message || 'Payment failed. Please check your details and try again.';
                        button.disabled = false;
                        button.textContent = 'Complete Payment';
                        button.style.backgroundColor = darkMode ? '#3B82F6' : '#2563EB';
                    } else if (result.paymentIntent) {
                        console.log("Payment succeeded:", result.paymentIntent);
                        // Don't reset button here - we're redirecting
                        successCallback(result.paymentIntent);
                    } else {
                        console.warn("Unknown payment result:", result);
                        errors.textContent = 'Unexpected payment response. Please try again.';
                        button.disabled = false;
                        button.textContent = 'Complete Payment';
                        button.style.backgroundColor = darkMode ? '#3B82F6' : '#2563EB';
                    }
                })
                .catch(err => {
                    console.error("Payment processing error:", err);
                    errors.textContent = err.message || 'An error occurred during payment processing.';
                    button.disabled = false;
                    button.textContent = 'Complete Payment';
                    button.style.backgroundColor = darkMode ? '#3B82F6' : '#2563EB';
                });
        });

        console.log("Mounting payment element...");
        const paymentElementContainer = document.getElementById('payment-element');
        if (paymentElementContainer) {
            paymentElementContainer.style.backgroundColor = darkMode ? '#1F2937' : '#FFFFFF';
            paymentElementContainer.style.padding = '16px';
            paymentElementContainer.style.borderRadius = '8px';
            paymentElementContainer.style.border = darkMode ? '1px solid #4B5563' : '1px solid #E5E7EB';
        }
        paymentElement.mount('#payment-element');
        console.log("Payment element mounted");

        console.log("Mounting billing address element...");
        const billingAddressContainer = document.getElementById('billing-address');
        if (billingAddressContainer) {
            billingAddressContainer.style.backgroundColor = darkMode ? '#1F2937' : '#FFFFFF';
            billingAddressContainer.style.padding = '16px';
            billingAddressContainer.style.borderRadius = '8px';
            billingAddressContainer.style.border = darkMode ? '1px solid #4B5563' : '1px solid #E5E7EB';
            billingAddressContainer.style.marginTop = '16px';
        }
        billingAddressElement.mount('#billing-address');
    });
}