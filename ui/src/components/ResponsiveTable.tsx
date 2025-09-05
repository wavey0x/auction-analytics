import React, { ReactNode } from 'react';
import { useIsMobile } from '../hooks/useIsMobile';

interface ResponsiveTableProps {
  desktopContent: ReactNode;
  mobileContent: ReactNode;
  breakpoint?: number;
}

const ResponsiveTable: React.FC<ResponsiveTableProps> = ({
  desktopContent,
  mobileContent,
  breakpoint = 768,
}) => {
  const isMobile = useIsMobile(breakpoint);

  return (
    <>
      {isMobile ? mobileContent : desktopContent}
    </>
  );
};

export default ResponsiveTable;