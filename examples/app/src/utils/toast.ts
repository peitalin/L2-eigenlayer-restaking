import { toast, ToastOptions, Id } from 'react-toastify';

// Types that match the original implementation
export type ToastType = 'success' | 'error' | 'info' | 'warning';

// Track active toasts to prevent duplicates
const activeToasts = new Map<string, Id>();

// Helper to create a consistent hash key for messages
const createMessageKey = (message: string, type: ToastType): string => {
  return `${message}_${type}`;
};

// Toast utility functions that mimic the original API
export const useToast = () => {
  // Show a toast notification
  const showToast = (message: string, type: ToastType = 'info', duration = 5000) => {
    const messageKey = createMessageKey(message, type);

    // Check if this exact toast is already displayed
    if (activeToasts.has(messageKey)) {
      // Update existing toast instead of creating a new one
      const id = activeToasts.get(messageKey);
      if (id) {
        // Just update the toast if it exists
        return id;
      }
    }

    const options: ToastOptions = {
      position: 'top-right',
      autoClose: duration,
      hideProgressBar: false,
      closeOnClick: true,
      pauseOnHover: true,
      draggable: true,
      // When toast closes, remove it from active toasts
      onClose: () => {
        activeToasts.delete(messageKey);
      }
    };

    let toastId: Id;

    switch (type) {
      case 'success':
        toastId = toast.success(message, options);
        break;
      case 'error':
        toastId = toast.error(message, options);
        break;
      case 'warning':
        toastId = toast.warning(message, options);
        break;
      case 'info':
      default:
        toastId = toast.info(message, options);
        break;
    }

    // Store the toast ID to prevent duplicates
    activeToasts.set(messageKey, toastId);
    return toastId;
  };

  // Hide a specific toast by ID
  const hideToast = (id: string) => {
    if (id) {
      toast.dismiss(id);
      // Clean up tracking
      for (const [key, value] of activeToasts.entries()) {
        if (value === id) {
          activeToasts.delete(key);
          break;
        }
      }
    }
  };

  // Return the same API as the original useToast hook
  return {
    showToast,
    hideToast,
    // For compatibility with existing code that might access toasts array
    toasts: [],
  };
};

// Single instance of the toast hook for direct exports
const toastInstance = useToast();

// Expose the toast functions directly for convenience
export const showToast = (message: string, type: ToastType = 'info', duration = 5000) => {
  return toastInstance.showToast(message, type, duration);
};

export const hideToast = (id: string) => {
  return toastInstance.hideToast(id);
};