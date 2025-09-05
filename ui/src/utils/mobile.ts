export const formatAddressForMobile = (address: string): string => {
  if (!address || address.length < 10) return address;
  return `${address.slice(0, 5)}...${address.slice(-3)}`;
};

export const formatTxHashForMobile = (txHash: string): string => {
  if (!txHash || txHash.length < 10) return txHash;
  return `${txHash.slice(0, 5)}...${txHash.slice(-3)}`;
};

export const formatAddressForDesktop = (address: string): string => {
  if (!address || address.length < 10) return address;
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
};

export const formatTxHashForDesktop = (txHash: string): string => {
  if (!txHash || txHash.length < 10) return txHash;
  return `${txHash.slice(0, 6)}...${txHash.slice(-4)}`;
};

export const getResponsiveSpacing = (isMobile: boolean) => ({
  container: isMobile ? 'px-2 py-2' : 'px-6 py-4',
  card: isMobile ? 'p-3' : 'p-4',
  section: isMobile ? 'mb-3' : 'mb-6',
  header: isMobile ? 'mb-2' : 'mb-4',
  tableCell: isMobile ? 'px-2 py-1' : 'px-4 py-2',
});

export const getResponsiveText = (isMobile: boolean) => ({
  heading: isMobile ? 'text-lg' : 'text-xl',
  subheading: isMobile ? 'text-base' : 'text-lg',
  body: isMobile ? 'text-sm' : 'text-base',
  caption: isMobile ? 'text-xs' : 'text-sm',
});

export const getMobileTouchTarget = () => ({
  minHeight: 'min-h-[44px]',
  padding: 'py-2 px-3',
  tap: 'active:scale-95 transition-transform',
});

export const copyToClipboard = async (text: string): Promise<boolean> => {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch (err) {
    // Fallback for older browsers
    try {
      const textArea = document.createElement('textarea');
      textArea.value = text;
      textArea.style.position = 'fixed';
      textArea.style.opacity = '0';
      document.body.appendChild(textArea);
      textArea.select();
      document.execCommand('copy');
      document.body.removeChild(textArea);
      return true;
    } catch (fallbackErr) {
      console.error('Failed to copy to clipboard:', fallbackErr);
      return false;
    }
  }
};

export const showToast = (message: string, type: 'success' | 'error' | 'info' = 'success') => {
  // Simple toast implementation - could be enhanced with a toast library
  const toast = document.createElement('div');
  toast.textContent = message;
  toast.className = `fixed top-4 right-4 px-4 py-2 rounded-lg text-white z-50 transition-all duration-300 ${
    type === 'success' ? 'bg-green-600' : 
    type === 'error' ? 'bg-red-600' : 
    'bg-blue-600'
  }`;
  
  document.body.appendChild(toast);
  
  // Animate in
  setTimeout(() => {
    toast.style.transform = 'translateX(0)';
    toast.style.opacity = '1';
  }, 10);
  
  // Remove after 3 seconds
  setTimeout(() => {
    toast.style.transform = 'translateX(100%)';
    toast.style.opacity = '0';
    setTimeout(() => {
      if (document.body.contains(toast)) {
        document.body.removeChild(toast);
      }
    }, 300);
  }, 3000);
};