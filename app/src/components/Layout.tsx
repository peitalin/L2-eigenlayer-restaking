import React, { ReactNode } from 'react';
import Navbar from './Navbar';
import Navigation from './Navigation';

interface LayoutProps {
  children: ReactNode;
}

const Layout: React.FC<LayoutProps> = ({ children }) => {
  return (
    <div className="app-container">
      <Navbar />
      <Navigation />
      <div className="content-container">
        {children}
      </div>
    </div>
  );
};

export default Layout;