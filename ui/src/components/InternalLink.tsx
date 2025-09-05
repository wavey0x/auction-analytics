import React, { useState } from 'react';
import { createPortal } from 'react-dom';
import { Link } from 'react-router-dom';
import { ChevronRight, ExternalLink, Copy, Check } from 'lucide-react';
import { cn, copyToClipboard, getChainInfo } from '../lib/utils';
import { useHoverTooltip } from '../hooks/useHoverTooltip';

interface InternalLinkProps {
  to: string;
  children: React.ReactNode;
  variant?: 'default' | 'address' | 'round' | 'take' | 'taker' | 'auction';
  className?: string;
  showArrow?: boolean;
  // Props for contextual actions
  address?: string;
  chainId?: number;
  showExternalLink?: boolean;
  showCopy?: boolean;
}

const InternalLink: React.FC<InternalLinkProps> = ({
  to,
  children,
  variant = 'default',
  className = '',
  showArrow = true,
  address,
  chainId,
  showExternalLink = false,
  showCopy = false,
}) => {
  const [copied, setCopied] = useState(false);
  
  const baseClasses = "internal-link group relative inline-flex items-center px-2 py-1 rounded-md border transition-all duration-200";
  
  const variantClasses = {
    default: "text-white hover:text-gray-300 border-gray-700 hover:border-gray-600",
    address: "text-white hover:text-gray-300 font-mono border-primary-500/40 hover:border-primary-400/60",
    auction: "text-white hover:text-gray-300 font-mono border-primary-600/50 hover:border-primary-500/70",
    round: "text-white hover:text-gray-300 font-mono font-semibold border-gray-500 hover:border-gray-400",
    take: "text-white hover:text-gray-300 font-mono font-semibold border-gray-600 hover:border-gray-500",
    taker: "text-white hover:text-gray-300 font-mono border-primary-400/40 hover:border-primary-300/60",
  };

  const chainInfo = chainId ? getChainInfo(chainId) : null;
  const hasExplorer = chainInfo && chainInfo.explorer !== "#";
  
  // Determine if contextual actions should be shown based on variant
  const showContextActions = (() => {
    if (variant === 'address' || variant === 'auction') {
      // Address/auction variants automatically show actions when address is provided
      return address && (hasExplorer || true); // Show copy always, external if explorer exists
    } else if (variant === 'round' || variant === 'take') {
      // Round and take variants never show contextual actions
      return false;
    } else if (variant === 'taker') {
      // Taker variant shows copy action only
      return address;
    } else {
      // Default variant respects explicit props
      return (showExternalLink && hasExplorer && address) || (showCopy && address);
    }
  })();

  const {
    isHovered,
    tooltipPosition,
    containerRef,
    handleMouseEnter,
    handleMouseLeave,
    handleTooltipMouseEnter,
    handleTooltipMouseLeave,
  } = useHoverTooltip({ enabled: showContextActions });

  const handleCopy = async (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (address) {
      const success = await copyToClipboard(address);
      if (success) {
        setCopied(true);
        setTimeout(() => setCopied(false), 600);
      }
    }
  };

  const handleExternalLink = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (hasExplorer && address) {
      const url = (variant === 'address' || variant === 'auction' || variant === 'taker')
        ? `${chainInfo.explorer}/address/${address}`
        : `${chainInfo.explorer}/address/${address}`;
      window.open(url, "_blank", "noopener,noreferrer");
    }
  };


  return (
    <>
      <div 
        ref={containerRef}
        className="relative inline-block internal-link-group"
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
      >
        {/* Main internal link button */}
        <Link
          to={to}
          className={cn(
            baseClasses,
            variantClasses[variant],
            className
          )}
        >
          <span>{children}</span>
          {showArrow && (
            <ChevronRight className="internal-link-icon h-3 w-3" />
          )}
        </Link>
      </div>

      {/* Portal-based tooltip that renders at document level */}
      {isHovered && createPortal(
        <div 
          className="fixed pointer-events-none z-50 transition-opacity duration-200"
          style={{
            left: tooltipPosition.x,
            top: tooltipPosition.y,
            transform: 'translateX(-50%)'
          }}
        >
          <div 
            className="flex items-center justify-center space-x-0.5 bg-gray-800 border border-gray-700 rounded-md p-1 shadow-lg pointer-events-auto"
            onMouseEnter={handleTooltipMouseEnter}
            onMouseLeave={handleTooltipMouseLeave}
          >
            {/* Copy icon first */}
            {((variant === 'address' && address) || (variant === 'auction' && address) || (variant === 'taker' && address) || (showCopy && address)) && (
              <button
                onClick={handleCopy}
                className="p-0.5 text-gray-500 hover:text-gray-300 transition-colors hover:scale-110"
                title="Copy address"
              >
                {copied ? (
                  <Check className="h-3 w-3 text-primary-400" />
                ) : (
                  <Copy className="h-3 w-3" />
                )}
              </button>
            )}
            
            {/* External link icon second */}
            {((variant === 'address' && hasExplorer && address) || (variant === 'auction' && hasExplorer && address) || (variant === 'taker' && hasExplorer && address) || (showExternalLink && hasExplorer && address)) && (
              <button
                onClick={handleExternalLink}
                className="p-0.5 text-gray-500 hover:text-primary-400 transition-colors hover:scale-110"
                title={`View on ${chainInfo.name} explorer`}
              >
                <ExternalLink className="h-3 w-3" />
              </button>
            )}
          </div>
        </div>,
        document.body
      )}
    </>
  );
};

export default InternalLink;