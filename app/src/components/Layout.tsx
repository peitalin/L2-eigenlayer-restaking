import React, { ReactNode } from 'react';
import Navbar from './Navbar';
import Navigation from './Navigation';
import EigenAgentInfo from './EigenAgentInfo';

interface LayoutProps {
  children?: ReactNode;
}

const Layout: React.FC<LayoutProps> = ({ children }) => {
  return (
    <div className="app-container">
      <Navbar />
      <Navigation />
      <div className="content-container">
          <div className="page-layout">
            <div className="left-column">
              {children}
            </div>
            <div className="right-column">
              <EigenAgentInfo />
            </div>
          </div>
      </div>
    </div>
  );
};

export default Layout;