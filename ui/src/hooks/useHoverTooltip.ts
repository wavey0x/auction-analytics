import { useState, useRef, useEffect } from "react";

export interface TooltipPosition {
  x: number;
  y: number;
}

export interface HoverTooltipOptions {
  enabled?: boolean;
  hideDelay?: number;  // Renamed from hoverDelay for clarity
  showDelay?: number;  // New: delay before showing tooltip
}

export interface HoverTooltipReturn {
  isHovered: boolean;
  tooltipPosition: TooltipPosition;
  containerRef: React.RefObject<HTMLDivElement>;
  handleMouseEnter: () => void;
  handleMouseLeave: () => void;
  handleTooltipMouseEnter: () => void;
  handleTooltipMouseLeave: () => void;
}

/**
 * Reusable hook for portal-based hover tooltips
 * Extracted from InternalLink component for consistent UX across components
 */
export const useHoverTooltip = (
  options: HoverTooltipOptions = {}
): HoverTooltipReturn => {
  const { enabled = true, hideDelay = 200, showDelay = 200 } = options;

  const [isHovered, setIsHovered] = useState(false);
  const [tooltipPosition, setTooltipPosition] = useState<TooltipPosition>({
    x: 0,
    y: 0,
  });
  const containerRef = useRef<HTMLDivElement>(null);
  const showTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const hideTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  const updateTooltipPosition = () => {
    if (containerRef.current) {
      const rect = containerRef.current.getBoundingClientRect();
      setTooltipPosition({
        x: rect.left + rect.width / 2,
        y: rect.bottom + 4,
      });
    }
  };

  const handleMouseEnter = () => {
    if (enabled) {
      // Clear any existing hide timeout
      if (hideTimeoutRef.current) {
        clearTimeout(hideTimeoutRef.current);
        hideTimeoutRef.current = null;
      }
      
      // Add delay before showing tooltip
      showTimeoutRef.current = setTimeout(() => {
        setIsHovered(true);
        updateTooltipPosition();
      }, showDelay);
    }
  };

  const handleMouseLeave = () => {
    if (enabled) {
      // Clear show timeout if tooltip hasn't appeared yet
      if (showTimeoutRef.current) {
        clearTimeout(showTimeoutRef.current);
        showTimeoutRef.current = null;
      }
      
      // Add delay before hiding if tooltip is currently visible
      if (isHovered) {
        hideTimeoutRef.current = setTimeout(() => {
          setIsHovered(false);
        }, hideDelay);
      }
    }
  };

  const handleTooltipMouseEnter = () => {
    // Cancel the hide timeout if cursor enters tooltip
    if (hideTimeoutRef.current) {
      clearTimeout(hideTimeoutRef.current);
      hideTimeoutRef.current = null;
    }
  };

  const handleTooltipMouseLeave = () => {
    // Hide immediately when leaving tooltip
    setIsHovered(false);
  };

  useEffect(() => {
    if (isHovered) {
      const handleScroll = () => updateTooltipPosition();
      window.addEventListener("scroll", handleScroll, true);
      window.addEventListener("resize", handleScroll);
      return () => {
        window.removeEventListener("scroll", handleScroll, true);
        window.removeEventListener("resize", handleScroll);
      };
    }
  }, [isHovered]);

  // Cleanup timeouts on unmount
  useEffect(() => {
    return () => {
      if (showTimeoutRef.current) {
        clearTimeout(showTimeoutRef.current);
      }
      if (hideTimeoutRef.current) {
        clearTimeout(hideTimeoutRef.current);
      }
    };
  }, []);

  return {
    isHovered,
    tooltipPosition,
    containerRef,
    handleMouseEnter,
    handleMouseLeave,
    handleTooltipMouseEnter,
    handleTooltipMouseLeave,
  };
};
