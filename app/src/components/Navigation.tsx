import React from 'react';
import { NavLink } from 'react-router-dom';

interface NavigationItem {
  path: string;
  label: string;
  exact?: boolean;
}

const Navigation: React.FC = () => {
  // Define navigation items - easy to add new ones in the future
  const navigationItems: NavigationItem[] = [
    { path: '/', label: 'Deposit', exact: true },
    { path: '/withdraw', label: 'Withdraw' }
    // Add more navigation items here as the app grows
  ];

  return (
    <nav className="navigation-panel">
      <ul className="navigation-list">
        {navigationItems.map((item) => (
          <li key={item.path} className="navigation-item">
            <NavLink
              to={item.path}
              className={({ isActive }) =>
                isActive ? "navigation-link active" : "navigation-link"
              }
              end={item.exact}
            >
              {item.label}
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  );
};

export default Navigation;