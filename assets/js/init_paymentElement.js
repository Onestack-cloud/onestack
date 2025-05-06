// The public key can be found in the Stripe Dashboard
const stripe = Stripe('pk_test_51P78jNFzZpjdOGbNf2cC0293N6PcRlU5DxOV1Ho5LgW6hEHB6g51cPprtYshWrpgQPQXQfgDEx8ogHRCWlvCN0Sp00IshzsYBC')

export const InitCheckout = {
    mounted() {
        console.log("InitCheckout hook mounted", this.el);
        console.log("Dataset secret:", this.el.dataset.secret);
        const successCallback = paymentIntent => { this.pushEvent('payment-success', paymentIntent) }
        init(this.el, successCallback)
    }
}

let paymentElement; // Define at module level so it can be referenced in change handlers

const init = (form, successCallback) => {
    const clientSecret = form.dataset.secret

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
            theme: 'stripe',
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

    // Initialize Elements with the client secret
    const elements = stripe.elements({
        appearance,
        clientSecret
    });

    // Create and mount the Payment Element with custom options
    const paymentElementOptions = {
        layout: "tabs",
        business: "Onestack"
    };

    paymentElement = elements.create("payment", paymentElementOptions);
    paymentElement.mount("#payment-element");

    // Handle theme changes
    const updatePaymentElementTheme = () => {
        const darkMode = isDarkMode();
        if (form.querySelector('#payment-element')) {
            try {
                // Only proceed if the payment element is still in the DOM
                paymentElement.unmount();
                // Create new elements instance with updated appearance
                const newElements = stripe.elements({
                    appearance: createAppearance(darkMode),
                    clientSecret
                });
                // Create and mount new payment element
                paymentElement = newElements.create("payment", paymentElementOptions);
                paymentElement.mount("#payment-element");
            } catch (e) {
                console.error("Failed to update payment element theme:", e);
            }
        }
    };

    // Listen for system theme preference changes
    const prefersDarkMediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
    if (prefersDarkMediaQuery.addEventListener) {
        prefersDarkMediaQuery.addEventListener('change', updatePaymentElementTheme);
    } else {
        // Fallback for older browsers
        prefersDarkMediaQuery.addListener(updatePaymentElementTheme);
    }

    // If your app supports a theme toggle, you can listen for changes to the data-theme attribute
    const htmlElement = document.documentElement;
    const observer = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
            if (mutation.type === 'attributes' && mutation.attributeName === 'data-theme') {
                updatePaymentElementTheme();
            }
        });
    });

    observer.observe(htmlElement, { attributes: true });

    // Handle errors that might be displayed in the Payment Element
    const messageContainer = document.getElementById('payment-message');

    // Show the loading UI during payment submission
    const setLoading = (isLoading) => {
        if (isLoading) {
            document.querySelector("#submit").disabled = true;
            document.querySelector("#spinner").classList.remove("hidden");
            document.querySelector("#button-text").classList.add("hidden");
        } else {
            document.querySelector("#submit").disabled = false;
            document.querySelector("#spinner").classList.add("hidden");
            document.querySelector("#button-text").classList.remove("hidden");
        }
    };

    // Show error messages
    const showMessage = (messageText) => {
        messageContainer.classList.remove("hidden");
        messageContainer.textContent = messageText;

        setTimeout(function () {
            messageContainer.classList.add("hidden");
            messageContainer.textContent = "";
        }, 4000);
    };

    // Handle form submission
    form.addEventListener('submit', async function (event) {
        event.preventDefault();

        setLoading(true);

        // Use confirmPayment instead of confirmCardPayment for the Payment Element
        const { error, paymentIntent } = await stripe.confirmPayment({
            elements,
            confirmParams: {
                // You can specify a return_url that redirects user after payment
                // For LiveView we'll handle the result in the callback
                return_url: window.location.origin + "/payment-complete",
            },
            redirect: "if_required"
        });

        if (error) {
            // This point is reached if there's an immediate error
            if (error.type === "card_error" || error.type === "validation_error") {
                showMessage(error.message);
            } else {
                showMessage("An unexpected error occurred.");
            }
            setLoading(false);
        } else if (paymentIntent && paymentIntent.status === 'succeeded') {
            // The payment succeeded!
            successCallback(paymentIntent);
        }
    });
}

// Custom styling for elements (maintained for reference)
const style = {
    base: {
        color: '#32325d',
        fontFamily: '"Helvetica Neue", Helvetica, sans-serif',
        fontSmoothing: 'antialiased',
        fontSize: '16px',
        '::placeholder': {
            color: '#aab7c4'
        }
    },
    invalid: {
        color: '#fa755a',
        iconColor: '#fa755a'
    }
}