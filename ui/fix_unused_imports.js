#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

// Common unused import patterns to fix automatically
const fixes = [
  // Icon imports that are unused
  { from: /import.*TrendingUp.*from 'lucide-react'/, to: "// Unused icon import" },
  { from: /import.*Users.*from 'lucide-react'/, to: "// Unused icon import" },
  { from: /import.*DollarSign.*from 'lucide-react'/, to: "// Unused icon import" },
  { from: /import.*Activity.*from 'lucide-react'/, to: "// Unused icon import" },
  { from: /import.*Volume2.*from 'lucide-react'/, to: "// Unused icon import" },
  { from: /import.*Clock.*from 'lucide-react'/, to: "// Unused icon import" },
  { from: /import.*Target.*from 'lucide-react'/, to: "// Unused icon import" },
  { from: /import.*Package.*from 'lucide-react'/, to: "// Unused icon import" },
  { from: /import.*ExternalLink.*from 'lucide-react'/, to: "// Unused icon import" },
  
  // React imports
  { from: /import React, { /, to: "import { " },
  { from: /import React from "react";/, to: "// React import not needed in modern setup" },
  { from: /import React from 'react';/, to: "// React import not needed in modern setup" },
  
  // Other common unused imports - skip regex for now
];

// Files to process (most problematic ones first)
const filesToProcess = [
  'src/pages/RoundDetails.tsx',
  'src/components/AuctionCard.tsx',
  'src/components/AddressTagManager.tsx',
  'src/components/ApiEndpoint.tsx',
  'src/components/BackButton.tsx',
  'src/components/CleanProgressBar.tsx',
  'src/components/ExpandedTokensList.tsx',
  'src/components/ExternalAddressLink.tsx',
  'src/components/IdentityRow.tsx',
  'src/components/Layout.tsx',
  'src/components/LiveDataBadge.tsx',
  'src/components/NotificationBubble.tsx',
  'src/components/RoundsTable.tsx',
  'src/components/SettingsModal.tsx',
];

function processFile(filePath) {
  if (!fs.existsSync(filePath)) {
    console.log(`File not found: ${filePath}`);
    return;
  }
  
  let content = fs.readFileSync(filePath, 'utf8');
  let changed = false;
  
  fixes.forEach(fix => {
    if (content.match(fix.from)) {
      content = content.replace(fix.from, fix.to);
      changed = true;
    }
  });
  
  if (changed) {
    fs.writeFileSync(filePath, content);
    console.log(`Fixed: ${filePath}`);
  }
}

console.log('Starting unused import cleanup...');
filesToProcess.forEach(processFile);
console.log('Done!');