import React, { useState } from "react";
import { Copy, Check, ExternalLink } from "lucide-react";
import { getTxLink, getChainInfo, cn } from "../lib/utils";
import { formatTxHashForMobile, formatTxHashForDesktop, copyToClipboard, showToast, getMobileTouchTarget } from "../utils/mobile";
import { useIsMobile } from "../hooks/useIsMobile";

interface MobileTxHashDisplayProps {
  txHash: string;
  chainId: number;
  className?: string;
  variant?: "inline" | "stacked";
  showCopy?: boolean;
  showExternalLink?: boolean;
}

const MobileTxHashDisplay: React.FC<MobileTxHashDisplayProps> = ({
  txHash,
  chainId,
  className = "",
  variant = "inline",
  showCopy = true,
  showExternalLink = true,
}) => {
  const [copied, setCopied] = useState(false);
  const isMobile = useIsMobile();
  const chainInfo = getChainInfo(chainId);
  const hasExplorer = chainInfo?.explorer && chainInfo.explorer !== "#";
  const touchTarget = getMobileTouchTarget();
  
  const formattedTxHash = isMobile 
    ? formatTxHashForMobile(txHash) 
    : formatTxHashForDesktop(txHash);

  const handleCopy = async (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    
    const success = await copyToClipboard(txHash);
    if (success) {
      setCopied(true);
      showToast("Transaction hash copied", "success");
      setTimeout(() => setCopied(false), 600);
    } else {
      showToast("Failed to copy transaction hash", "error");
    }
  };

  const handleExplorerClick = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (hasExplorer) {
      const url = getTxLink(txHash, chainId);
      window.open(url, "_blank", "noopener,noreferrer");
    }
  };

  if (variant === "stacked" && isMobile) {
    return (
      <div className={cn("flex flex-col items-start space-y-1", className)}>
        <span className="font-mono text-sm text-gray-400 select-all">
          {formattedTxHash}
        </span>
        <div className="flex items-center space-x-2">
          {showCopy && (
            <button
              onClick={handleCopy}
              className={cn(
                "flex items-center justify-center rounded-md bg-gray-800 text-gray-400 hover:text-gray-200 hover:bg-gray-700 transition-all duration-200",
                touchTarget.minHeight,
                touchTarget.padding,
                touchTarget.tap
              )}
              title="Copy transaction hash"
            >
              {copied ? (
                <Check className="h-4 w-4 text-primary-400" />
              ) : (
                <Copy className="h-4 w-4" />
              )}
            </button>
          )}
          {showExternalLink && hasExplorer && (
            <button
              onClick={handleExplorerClick}
              className={cn(
                "flex items-center justify-center rounded-md bg-gray-800 text-gray-400 hover:text-primary-400 hover:bg-gray-700 transition-all duration-200",
                touchTarget.minHeight,
                touchTarget.padding,
                touchTarget.tap
              )}
              title={`View transaction on ${chainInfo?.name} explorer`}
            >
              <ExternalLink className="h-4 w-4" />
            </button>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className={cn("inline-flex items-center space-x-1", className)}>
      <span className="font-mono text-sm text-gray-400 select-all">
        {formattedTxHash}
      </span>
      
      {showCopy && (
        <button
          onClick={handleCopy}
          className={cn(
            "flex items-center justify-center text-gray-500 hover:text-gray-300 transition-all duration-200",
            isMobile ? `${touchTarget.minHeight} ${touchTarget.padding} ${touchTarget.tap}` : "p-1 hover:scale-110"
          )}
          title="Copy transaction hash"
        >
          {copied ? (
            <Check className={cn("text-primary-400", isMobile ? "h-4 w-4" : "h-3 w-3")} />
          ) : (
            <Copy className={cn(isMobile ? "h-4 w-4" : "h-3 w-3")} />
          )}
        </button>
      )}
      
      {showExternalLink && hasExplorer && (
        <button
          onClick={handleExplorerClick}
          className={cn(
            "flex items-center justify-center text-gray-500 hover:text-primary-400 transition-all duration-200",
            isMobile ? `${touchTarget.minHeight} ${touchTarget.padding} ${touchTarget.tap}` : "p-1 hover:scale-110"
          )}
          title={`View transaction on ${chainInfo?.name} explorer`}
        >
          <ExternalLink className={cn(isMobile ? "h-4 w-4" : "h-3 w-3")} />
        </button>
      )}
    </div>
  );
};

export default MobileTxHashDisplay;