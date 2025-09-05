import React, { ReactNode } from 'react';
import { cn } from '../lib/utils';
import { getResponsiveSpacing } from '../utils/mobile';
import { useIsMobile } from '../hooks/useIsMobile';

interface MobileCardProps {
  children: ReactNode;
  className?: string;
  onClick?: () => void;
  isClickable?: boolean;
}

const MobileCard: React.FC<MobileCardProps> = ({
  children,
  className = "",
  onClick,
  isClickable = false,
}) => {
  const isMobile = useIsMobile();
  const spacing = getResponsiveSpacing(isMobile);

  return (
    <div
      className={cn(
        "rounded-lg border border-gray-800 bg-gray-900/50 backdrop-blur-sm transition-all duration-200",
        spacing.card,
        isClickable && "cursor-pointer hover:bg-gray-800/50 hover:border-gray-700 active:scale-[0.98]",
        className
      )}
      onClick={onClick}
    >
      {children}
    </div>
  );
};

export default MobileCard;