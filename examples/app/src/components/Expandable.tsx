import React, { useState, ReactNode } from 'react';

interface ExpandableProps {
  title: string;
  children: ReactNode;
  initialExpanded?: boolean;
  className?: string;
}

const Expandable: React.FC<ExpandableProps> = ({
  title,
  children,
  initialExpanded = false,
  className = ''
}) => {
  const [isExpanded, setIsExpanded] = useState(initialExpanded);

  const toggleExpand = () => {
    setIsExpanded(!isExpanded);
  };

  return (
    <div className={`expandable-section ${className}`}>
      <div
        className={`expandable-header ${isExpanded ? 'expanded' : 'collapsed'}`}
        onClick={toggleExpand}
      >
        <h3>{title}</h3>
        <span className={`expandable-icon ${isExpanded ? 'expanded' : ''}`}>
          ▼
        </span>
      </div>
      {isExpanded && (
        <div className="expandable-content">
          {children}
        </div>
      )}
    </div>
  );
};

export default Expandable;